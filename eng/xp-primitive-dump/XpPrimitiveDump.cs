// Phase 2A slim-plan item 2: dump the results of DirectDraw-owned facade
// operations (bltFast, blt incl. stretch, source color key, clip rect, fill,
// HitTest, drawPolygon/drawBox, createBitmap, createFromImage/createSprite)
// executed by the real XP runtime through a packaged DirectDraw.net.dll.
//
// Needs dx7vb.dll and DirectDraw: run it only in the XP SP3 x86 VM. Build with
// eng/xp-primitive-dump/xp-primitive-dump.ps1 (CLR 2, x86). Runbook and output
// format: docs/modernization/phase2a-slim-plan.md item 2 and
// fixtures/xp-primitive-dumps/README.md.
//
//   XpPrimitiveDump list
//       print the case list (no DirectDraw; safe on any host)
//   XpPrimitiveDump dump <package-dir> <out-root> <label> [--vbox <version>] [--graphics <controller>]
//       write <out-root>\<label>\<mode>\{index.json,<id>.bin} and <out-root>\environment.json
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using DxVBLib;
using Microsoft.Win32;
using org.kohsuke.directdraw;

namespace FreeTrain.XpPrimitiveDump
{
	// One case of the fixed list. Pure data, so `list` never touches DirectDraw.
	sealed class Case
	{
		public string Id, Op;
		public int[] Dst;            // { width, height }
		public int[] Src;            // { width, height } or null
		public int[] Args = new int[0];
		public bool SrcKey;          // set sourceColorKey on the source (or on the tested surface for hitTest)
		public int Key = Cases.Magenta;
		public int Color;            // fill colour (ARGB)
		public int[] Clip;           // clipRect { x, y, w, h } set before the operation
		public bool ResetClip;       // resetClipRect() after setting Clip
		public int[][] Points;
		public int DstSeed, SrcSeed;

		// Results
		public string Error = "none";
		public string[] Results;
		public int[] ClipEffective;
		public int[] DrawState;
		public int DstPitch, SrcPitch;
		public List<KeyValuePair<string, byte[]>> Blocks = new List<KeyValuePair<string, byte[]>>();
		public int ChangedPixels = -1;
		public int[] ChangedBounds;
		public string PaddingIntact = "null", SourceUnchanged = "null";
		public string HarnessError;
	}

	static class Cases
	{
		public const int Magenta = unchecked((int)0xFFFF00FF);
		public const int Odd = unchecked((int)0xFF874321);    // low bits set in every channel
		public const int Dim = unchecked((int)0xFF080408);    // vanishes in 16-bit modes
		public const int White = unchecked((int)0xFFFFFFFF);
		public const int NearMagenta = unchecked((int)0xFFFA03FA);  // equals Magenta after 16-bit truncation

		// Same geometries as eng/native-vectors/NativeVectorProbe.cs:
		// { dstW, dstH, srcW, srcH, dx, dy, sx1, sy1, sx2, sy2 }. DirectDraw picks the
		// pitch, so "odd-width" replaces the probe's chosen padding.
		static readonly int[][] Geometries = {
			new[] { 16, 8,  16, 8,   0, 0,   0, 0, 16, 8 },
			new[] { 17, 9,  13, 7,   2, 1,   0, 0, 13, 7 },
			new[] { 16, 8,  12, 6,  -3, -2,  0, 0, 12, 6 },
			new[] { 16, 8,  12, 6,   9, 5,   0, 0, 12, 6 },
			new[] { 16, 8,  12, 6,   1, 1,   3, 2, 10, 5 },
		};
		static readonly string[] GeometryNames = { "aligned", "odd-width", "negative-dest", "overrun", "sub-rect" };

		static int seed = 1000;

		static Case Make(string id, string op, int[] dst, int[] src)
		{
			Case c = new Case();
			c.Id = id; c.Op = op; c.Dst = dst; c.Src = src;
			c.DstSeed = seed++; c.SrcSeed = seed++;
			return c;
		}

		// blt/bltFast args: { dx, dy, sx, sy, w, h }.
		static Case Copy(string op, string prefix, int g, bool key)
		{
			int[] k = Geometries[g];
			Case c = Make(prefix + "-" + GeometryNames[g], op, new[] { k[0], k[1] }, new[] { k[2], k[3] });
			c.Args = new[] { k[4], k[5], k[6], k[7], k[8] - k[6], k[9] - k[7] };
			c.SrcKey = key;
			return c;
		}

		static Case Stretch(string id, int[] dst, int[] src, bool key, params int[] args)
		{
			Case c = Make(id, "bltStretch", dst, src);
			c.Args = args; c.SrcKey = key;
			return c;
		}

		static Case Fill(string id, int[] dst, int color, params int[] rect)
		{
			Case c = Make(id, rect.Length == 0 ? "fill" : "fillRect", dst, null);
			c.Args = rect; c.Color = color;
			return c;
		}

		static int[] P(int x, int y) { return new[] { x, y }; }

		public static List<Case> Build()
		{
			seed = 1000;
			List<Case> l = new List<Case>();
			int[] d16 = { 16, 8 }, d17 = { 17, 9 }, s8 = { 8, 4 };

			// bltFast always passes DDBLTFAST_SRCCOLORKEY and does no managed clipping.
			for (int g = 0; g < Geometries.Length; g++) l.Add(Copy("bltFast", "bltFast-key", g, true));
			l.Add(Copy("bltFast", "bltFast-nokey", 0, false));
			l.Add(Copy("bltFast", "bltFast-nokey", 4, false));

			// blt(Point, Surface, Point, Size): managed Util.clip, then DDBLT_KEYSRC if keyed.
			for (int g = 0; g < Geometries.Length; g++) l.Add(Copy("blt", "blt-key", g, true));
			foreach (int g in new[] { 0, 2, 3 }) l.Add(Copy("blt", "blt-nokey", g, false));
			Case t = Copy("blt", "blt-key-truncated", 0, true);
			t.Key = NearMagenta;
			l.Add(t);

			// Clip rect: set, intersected with the surface by the setter, then blt.
			foreach (object[] clip in new object[][] {
				new object[] { "inner", new[] { 3, 2, 7, 3 }, false },
				new object[] { "beyond-surface", new[] { -5, -5, 100, 100 }, false },
				new object[] { "disjoint", new[] { 20, 20, 4, 4 }, false },
				new object[] { "reset", new[] { 3, 2, 7, 3 }, true },
			}) {
				Case c = Copy("blt", "blt-clip-" + clip[0], 0, true);
				c.Clip = (int[])clip[1]; c.ResetClip = (bool)clip[2];
				l.Add(c);
			}
			Case cn = Copy("blt", "blt-clip-inner", 2, true);
			cn.Id = "blt-clip-inner-negative-dest";
			cn.Clip = new[] { 3, 2, 7, 3 };
			l.Add(cn);

			// Stretch: blt(dx1, dy1, dx2, dy2, src, sx1, sy1, sx2, sy2). Util.clip adjusts the
			// source 1:1 even when stretching; that is part of what is recorded.
			l.Add(Stretch("bltStretch-up2x", d16, s8, false, 0, 0, 16, 8, 0, 0, 8, 4));
			l.Add(Stretch("bltStretch-down", d16, d16, false, 1, 1, 8, 4, 0, 0, 16, 8));
			l.Add(Stretch("bltStretch-odd", d17, new[] { 13, 7 }, false, 1, 1, 15, 8, 2, 1, 11, 6));
			l.Add(Stretch("bltStretch-key-up2x", d16, s8, true, 0, 0, 16, 8, 0, 0, 8, 4));
			l.Add(Stretch("bltStretch-negative-dest", d16, s8, false, -4, -2, 12, 6, 0, 0, 8, 4));
			l.Add(Stretch("bltStretch-overrun", d16, s8, false, 8, 4, 24, 12, 0, 0, 8, 4));
			l.Add(Stretch("bltStretch-mirror", d16, s8, false, 16, 0, 0, 8, 0, 0, 8, 4));
			Case sc = Stretch("bltStretch-clip-up2x", d16, s8, false, 0, 0, 16, 8, 0, 0, 8, 4);
			sc.Clip = new[] { 2, 1, 10, 5 };
			l.Add(sc);

			// fill(Color) fills the clip rect; fill(Rectangle, Color) intersects with it.
			l.Add(Fill("fill-whole-odd", d17, Odd));
			l.Add(Fill("fill-whole-white", d16, White));
			l.Add(Fill("fill-whole-dim", d16, Dim));
			Case fc = Fill("fill-whole-clip", d17, Odd);
			fc.Clip = new[] { 3, 2, 7, 3 };
			l.Add(fc);
			l.Add(Fill("fillRect-inner", d17, Odd, 2, 1, 9, 5));
			l.Add(Fill("fillRect-negative", d17, Odd, -3, -2, 8, 5));
			l.Add(Fill("fillRect-overrun", d17, Odd, 12, 6, 10, 10));
			l.Add(Fill("fillRect-outside", d17, Odd, 20, 20, 4, 4));
			Case fr = Fill("fillRect-clip", d17, Odd, 0, 0, 8, 8);
			fr.Clip = new[] { 3, 2, 7, 3 };
			l.Add(fr);

			// HitTest on a keyed pattern (every 5th pixel is the key, every 7th black).
			int[][] probes = { P(0, 0), P(1, 0), P(5, 0), P(2, 1), P(7, 0), P(16, 8), P(-1, 0), P(0, -1),
				P(17, 0), P(0, 9), P(17, 9), P(18, 0) };
			Case hk = Make("hitTest-key", "hitTest", d17, null);
			hk.SrcKey = true; hk.Points = probes;
			l.Add(hk);
			Case hn = Make("hitTest-nokey", "hitTest", d17, null);
			hn.Points = probes;
			l.Add(hn);

			// GDI Polygon through GetDC with the DC's default pen and brush.
			foreach (object[] poly in new object[][] {
				new object[] { "diamond", new[] { P(8, 0), P(16, 4), P(8, 8), P(0, 4) } },
				new object[] { "negative", new[] { P(-4, -2), P(10, -2), P(10, 6), P(-4, 6) } },
				new object[] { "overrun", new[] { P(10, 5), P(20, 5), P(20, 12), P(10, 12) } },
			}) {
				Case c = Make("drawPolygon-" + poly[0], "drawPolygon", d17, null);
				c.Points = (int[][])poly[1];
				l.Add(c);
			}

			// DrawBox(Left, Top, Right, Bottom) with the surface's default draw state.
			foreach (object[] box in new object[][] {
				new object[] { "inner", new[] { 2, 1, 9, 5 } },
				new object[] { "negative", new[] { -3, -2, 8, 5 } },
				new object[] { "overrun", new[] { 12, 6, 10, 10 } },
			}) {
				Case c = Make("drawBox-" + box[0], "drawBox", d17, null);
				c.Args = (int[])box[1];
				l.Add(c);
			}

			l.Add(Make("createBitmap-aligned", "createBitmap", d16, null));
			l.Add(Make("createBitmap-odd", "createBitmap", d17, null));

			// createFromImage draws a seeded opaque bitmap into a new surface through GDI+;
			// createSprite also keys on its top-left pixel, then blt()s onto a seeded target.
			l.Add(Make("createFromImage-odd", "createFromImage", null, d17));
			Case sp = Make("createSprite-blt", "createSprite", d16, d17);
			sp.Args = new[] { -2, 1 };
			l.Add(sp);
			return l;
		}
	}

	public static class Program
	{
		internal static string PackageDir;
		static readonly string[] PackageAssemblies = { "DirectDraw.net", "Interop.DxVBLib", "Interop.DirectDrawAlphaBlendLib" };

		// The package copies are loaded by path, so one tool binary serves both the
		// reconstructed and the official DirectDraw.net.dll (neither is strong-named).
		static Assembly Resolve(object sender, ResolveEventArgs e)
		{
			string name = new AssemblyName(e.Name).Name;
			foreach (string a in PackageAssemblies)
				if (string.Equals(a, name, StringComparison.OrdinalIgnoreCase))
					return Assembly.LoadFrom(Path.Combine(PackageDir, a + ".dll"));
			return null;
		}

		[STAThread]
		public static int Main(string[] args)
		{
			if (args.Length == 1 && args[0] == "list") {
				foreach (Case c in Cases.Build()) Console.WriteLine("{0,-32} {1}", c.Id, c.Op);
				return 0;
			}
			if (args.Length < 4 || args[0] != "dump") {
				Console.Error.WriteLine("usage: XpPrimitiveDump list");
				Console.Error.WriteLine("       XpPrimitiveDump dump <package-dir> <out-root> <label> [--vbox <version>] [--graphics <controller>]");
				return 2;
			}
			PackageDir = Path.GetFullPath(args[1]);
			AppDomain.CurrentDomain.AssemblyResolve += Resolve;
			return Dumper.Run(args);
		}
	}

	// Everything that touches DirectDraw.net / DxVBLib types lives here, so that
	// the AssemblyResolve handler is installed before any of it is JIT-compiled.
	static class Dumper
	{
		const string AlphaBlendSha256 = "b8153302a76f3768528453d18c9025a5017b0b5ea2350f9b3f57a8a2b37f165d";
		const byte PadByte = 0xA5;

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
		static extern IntPtr LoadLibraryW(string path);
		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		static extern IntPtr GetProcAddress(IntPtr module, string name);
		[UnmanagedFunctionPointer(CallingConvention.StdCall)]
		delegate int DllRegisterServerFn();

		static DirectDraw dd;
		static int bitCount, bpp, rMask, gMask, bMask;
		static int wr, wg, wb;
		static bool raw;            // raw locked memory (true) or GetLockedPixel/SetLockedPixel
		static string accessNote;

		public static int Run(string[] args)
		{
			string outRoot = Path.GetFullPath(args[2]), label = args[3];
			string vbox = "unrecorded", graphics = "unrecorded";
			for (int i = 4; i + 1 < args.Length; i += 2) {
				if (args[i] == "--vbox") vbox = args[i + 1];
				else if (args[i] == "--graphics") graphics = args[i + 1];
				else { Console.Error.WriteLine("unknown option " + args[i]); return 2; }
			}
			if (IntPtr.Size != 4) throw new Exception("run as x86");

			// The facade's Surface statically activates AlphaBlenderClass, so the package's
			// native DLL must be registered first, exactly as tools/Driver/Driver.cs does.
			string alpha = Path.Combine(Program.PackageDir, "DirectDraw.AlphaBlend.dll");
			if (Sha(File.ReadAllBytes(alpha)) != AlphaBlendSha256) throw new Exception("unexpected DirectDraw.AlphaBlend.dll hash: " + alpha);
			IntPtr module = LoadLibraryW(alpha);
			if (module == IntPtr.Zero) throw new Exception("LoadLibrary failed: " + Marshal.GetLastWin32Error());
			IntPtr reg = GetProcAddress(module, "DllRegisterServer");
			int regHr = ((DllRegisterServerFn)Marshal.GetDelegateForFunctionPointer(reg, typeof(DllRegisterServerFn)))();
			if (regHr != 0) throw new Exception("DllRegisterServer 0x" + regHr.ToString("x8"));

			dd = new DirectDraw();
			DirectDraw.SurfeceAllocation = DDSurfaceAllocation.ForceSystemMem;
			string mode = DetectFormat();
			Console.WriteLine("package {0}: pixel format {1}, access {2}", Program.PackageDir, mode, accessNote);

			string dir = Path.Combine(Path.Combine(outRoot, label), mode);
			if (File.Exists(Path.Combine(dir, "index.json"))) {
				Console.Error.WriteLine("refusing to overwrite existing dump " + dir);
				return 1;
			}

			List<Case> cases = Cases.Build();
			foreach (Case c in cases) {
				try { Execute(c); }
				catch (Exception e) { c.HarnessError = e.GetType().Name + ": " + e.Message; }
			}

			Directory.CreateDirectory(dir);
			foreach (Case c in cases)
				if (c.HarnessError == null) File.WriteAllBytes(Path.Combine(dir, c.Id + ".bin"), Bytes(c));
			File.WriteAllText(Path.Combine(dir, "index.json"), Index(label, mode, cases), new UTF8Encoding(false));
			WriteEnvironment(outRoot, vbox, graphics);

			int failed = 0;
			foreach (Case c in cases) {
				if (c.HarnessError != null) { failed++; Console.WriteLine("  HARNESS FAIL {0}: {1}", c.Id, c.HarnessError); }
				else if (c.Error != "none") Console.WriteLine("  {0}: {1}", c.Id, c.Error);
			}
			Console.WriteLine("{0}\\{1}: {2} cases, {3} harness failures -> {4}", label, mode, cases.Count, failed, dir);
			return failed == 0 ? 0 : 1;
		}

		// ---- pixel format and memory access ------------------------------------

		static string DetectFormat()
		{
			Surface s = dd.createOffscreenSurface(17, 9);
			try {
				DDPIXELFORMAT pf = new DDPIXELFORMAT();
				s.handle.GetPixelFormat(ref pf);
				bitCount = pf.lRGBBitCount; rMask = pf.lRBitMask; gMask = pf.lGBitMask; bMask = pf.lBBitMask;
				if (bitCount <= 8) throw new Exception("palettized display mode; set the desktop to 16 or 32 bits per pixel");
				bpp = bitCount / 8;
				wr = Width(rMask); wg = Width(gMask); wb = Width(bMask);

				// Prefer raw locked memory (shows pitch and padding); fall back to the
				// dx7vb per-pixel accessors if lpSurface is unusable.
				int[] pattern = PatternValues(17, 9, 7, -1);
				DDSURFACEDESC2 desc = new DDSURFACEDESC2();
				RECT r = Full(s);
				s.handle.Lock(ref r, ref desc, CONST_DDLOCKFLAGS.DDLOCK_WAIT, 0);
				try {
					if (desc.lpSurface == 0 || desc.lPitch < 17 * bpp) {
						accessNote = "locked-pixel (lpSurface " + desc.lpSurface + ", pitch " + desc.lPitch + ")";
					} else {
						WriteRaw(desc, 17, 9, pattern);
						bool ok = true;
						for (int y = 0; y < 9 && ok; y++)
							for (int x = 0; x < 17 && ok; x++)
								ok = (s.handle.GetLockedPixel(x, y) & PixelMask) == pattern[y * 17 + x];
						raw = ok;
						accessNote = ok ? "raw-lock" : "locked-pixel (raw write not visible through GetLockedPixel)";
					}
				} finally { s.handle.Unlock(ref r); }
			} finally { s.Dispose(); }

			if (bitCount == 16 && gMask == 0x7e0) return "565";
			if (bitCount == 16 && gMask == 0x3e0) return "555";
			if (bitCount == 24 || bitCount == 32) return bitCount.ToString();
			return string.Format("bpp{0}-{1:x}-{2:x}-{3:x}", bitCount, rMask, gMask, bMask);
		}

		static int PixelMask { get { return bpp == 4 ? -1 : (1 << bitCount) - 1; } }

		static byte Width(int mask)
		{
			uint i = (uint)mask;
			while ((i & 1) == 0) i >>= 1;
			byte w = 0;
			while (i != 0) { i >>= 1; w++; }
			return w;
		}

		// The facade's private colorToFill, restated.
		static int ToFill(int argb)
		{
			Color c = Color.FromArgb(argb);
			uint x = 0;
			x |= ((uint)c.R) >> (8 - wr);
			x <<= wg;
			x |= ((uint)c.G) >> (8 - wg);
			x <<= wb;
			x |= ((uint)c.B) >> (8 - wb);
			return (int)x;
		}

		static RECT Full(Surface s)
		{
			RECT r = new RECT();
			r.Right = s.size.Width; r.Bottom = s.size.Height;
			return r;
		}

		// Seeded values restricted to the RGB masks. key >= 0: every 5th pixel is the
		// key and every 7th is black, so keyed and unkeyed paths both run.
		static int[] PatternValues(int w, int h, int seed, int key)
		{
			Random rnd = new Random(seed);
			int mask = rMask | gMask | bMask;
			int[] v = new int[w * h];
			for (int y = 0; y < h; y++)
				for (int x = 0; x < w; x++) {
					int p = rnd.Next() & mask;
					int n = x + y * 3;
					if (key >= 0 && n % 5 == 0) p = key;
					else if (key >= 0 && n % 7 == 0) p = 0;
					v[y * w + x] = p;
				}
			return v;
		}

		static void WriteRaw(DDSURFACEDESC2 desc, int w, int h, int[] values)
		{
			byte[] row = new byte[desc.lPitch];
			for (int y = 0; y < h; y++) {
				for (int i = 0; i < row.Length; i++) row[i] = PadByte;
				for (int x = 0; x < w; x++)
					for (int k = 0; k < bpp; k++) row[x * bpp + k] = (byte)(values[y * w + x] >> (8 * k));
				Marshal.Copy(row, 0, new IntPtr(desc.lpSurface + y * desc.lPitch), row.Length);
			}
		}

		static void Seed(Surface s, int seed, int key)
		{
			int w = s.size.Width, h = s.size.Height;
			int[] values = PatternValues(w, h, seed, key);
			DDSURFACEDESC2 desc = new DDSURFACEDESC2();
			RECT r = Full(s);
			s.handle.Lock(ref r, ref desc, CONST_DDLOCKFLAGS.DDLOCK_WAIT, 0);
			try {
				if (raw) WriteRaw(desc, w, h, values);
				else for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) s.handle.SetLockedPixel(x, y, values[y * w + x]);
			} finally { s.handle.Unlock(ref r); }
		}

		// Raw: pitch * height bytes of locked memory. Pixel access: width * bpp per row.
		static byte[] Read(Surface s, out int pitch)
		{
			int w = s.size.Width, h = s.size.Height;
			DDSURFACEDESC2 desc = new DDSURFACEDESC2();
			RECT r = Full(s);
			s.handle.Lock(ref r, ref desc, CONST_DDLOCKFLAGS.DDLOCK_WAIT | CONST_DDLOCKFLAGS.DDLOCK_READONLY, 0);
			try {
				if (raw) {
					pitch = desc.lPitch;
					byte[] b = new byte[pitch * h];
					Marshal.Copy(new IntPtr(desc.lpSurface), b, 0, b.Length);
					return b;
				}
				pitch = w * bpp;
				byte[] o = new byte[pitch * h];
				for (int y = 0; y < h; y++)
					for (int x = 0; x < w; x++) {
						int v = s.handle.GetLockedPixel(x, y);
						for (int k = 0; k < bpp; k++) o[y * pitch + x * bpp + k] = (byte)(v >> (8 * k));
					}
				return o;
			} finally { s.handle.Unlock(ref r); }
		}

		// ---- case execution -----------------------------------------------------

		static Surface New(int[] size) { return dd.createOffscreenSurface(size[0], size[1]); }

		static void Execute(Case c)
		{
			switch (c.Op) {
			case "createBitmap": ExecCreateBitmap(c); return;
			case "createFromImage": ExecCreateFromImage(c); return;
			case "createSprite": ExecCreateSprite(c); return;
			}

			Surface dst = New(c.Dst);
			Surface src = c.Src == null ? null : New(c.Src);
			try {
				int key = ToFill(c.Key);
				if (src != null) {
					Seed(dst, c.DstSeed, -1);
					Seed(src, c.SrcSeed, key);
					if (c.SrcKey) src.sourceColorKey = Color.FromArgb(c.Key);
				} else {
					Seed(dst, c.DstSeed, c.Op == "hitTest" ? key : -1);
					if (c.SrcKey) dst.sourceColorKey = Color.FromArgb(c.Key);
				}
				byte[] srcBefore = null;
				if (src != null) { srcBefore = Read(src, out c.SrcPitch); c.Blocks.Add(Block("src", srcBefore)); }
				byte[] before = Read(dst, out c.DstPitch);
				c.Blocks.Add(Block("dstBefore", before));

				if (c.Clip != null) {
					dst.clipRect = new Rectangle(c.Clip[0], c.Clip[1], c.Clip[2], c.Clip[3]);
					if (c.ResetClip) dst.resetClipRect();
					Rectangle e = dst.clipRect;
					c.ClipEffective = new[] { e.X, e.Y, e.Width, e.Height };
				}
				if (c.Op == "drawBox") {
					DirectDrawSurface7 h = dst.handle;
					c.DrawState = new[] { h.GetForeColor(), h.GetFillColor(), h.GetFillStyle(), h.getDrawWidth(), h.getDrawStyle() };
				}

				try { Operate(c, dst, src); }
				catch (COMException e) { c.Error = string.Format("0x{0:x8}", e.ErrorCode); }
				catch (Exception e) { c.Error = e.GetType().FullName; }

				int pitch;
				byte[] after = Read(dst, out pitch);
				c.Blocks.Add(Block("dstAfter", after));
				Compare(c, before, after, c.Dst[0], c.Dst[1], c.DstPitch);
				if (src != null) {
					int sp;
					c.SourceUnchanged = Same(srcBefore, Read(src, out sp)) ? "true" : "false";
				}
			} finally {
				dst.Dispose();
				if (src != null) src.Dispose();
			}
		}

		static void Operate(Case c, Surface dst, Surface src)
		{
			int[] a = c.Args;
			switch (c.Op) {
			case "bltFast":
				dst.bltFast(a[0], a[1], src, new Rectangle(a[2], a[3], a[4], a[5]));
				break;
			case "blt":
				dst.blt(new Point(a[0], a[1]), src, new Point(a[2], a[3]), new Size(a[4], a[5]));
				break;
			case "bltStretch":
				dst.blt(a[0], a[1], a[2], a[3], src, a[4], a[5], a[6], a[7]);
				break;
			case "fill":
				dst.fill(Color.FromArgb(c.Color));
				break;
			case "fillRect":
				dst.fill(new Rectangle(a[0], a[1], a[2], a[3]), Color.FromArgb(c.Color));
				break;
			case "hitTest":
				c.Results = new string[c.Points.Length];
				for (int i = 0; i < c.Points.Length; i++) {
					try { c.Results[i] = dst.HitTest(c.Points[i][0], c.Points[i][1]) ? "true" : "false"; }
					catch (COMException e) { c.Results[i] = string.Format("0x{0:x8}", e.ErrorCode); }
					catch (Exception e) { c.Results[i] = e.GetType().FullName; }
				}
				break;
			case "drawPolygon":
				int[][] p = c.Points;
				dst.drawPolygon(new Point(p[0][0], p[0][1]), new Point(p[1][0], p[1][1]),
					new Point(p[2][0], p[2][1]), new Point(p[3][0], p[3][1]));
				break;
			case "drawBox":
				dst.drawBox(new Rectangle(a[0], a[1], a[2], a[3]));
				break;
			default:
				throw new Exception("unknown op " + c.Op);
			}
		}

		static void ExecCreateBitmap(Case c)
		{
			Surface s = New(c.Dst);
			try {
				Seed(s, c.DstSeed, -1);
				byte[] surface = Read(s, out c.DstPitch);
				c.Blocks.Add(Block("surface", surface));
				try {
					using (Bitmap b = s.createBitmap()) c.Blocks.Add(Block("bitmap", BitmapBytes(b)));
				} catch (COMException e) { c.Error = string.Format("0x{0:x8}", e.ErrorCode); }
				catch (Exception e) { c.Error = e.GetType().FullName; }
				int pitch;
				c.SourceUnchanged = Same(surface, Read(s, out pitch)) ? "true" : "false";
			} finally { s.Dispose(); }
		}

		// Seeded opaque 32bppArgb image; top-left pixel (and every 5th) is magenta.
		static Bitmap SeedImage(int[] size, int seed)
		{
			Random rnd = new Random(seed);
			Bitmap b = new Bitmap(size[0], size[1], PixelFormat.Format32bppArgb);
			for (int y = 0; y < size[1]; y++)
				for (int x = 0; x < size[0]; x++) {
					int v = rnd.Next() & 0xffffff;
					b.SetPixel(x, y, (x + y * 3) % 5 == 0 ? Color.FromArgb(Cases.Magenta) : Color.FromArgb(unchecked((int)0xFF000000) | v));
				}
			return b;
		}

		static void ExecCreateFromImage(Case c)
		{
			using (Bitmap img = SeedImage(c.Src, c.SrcSeed)) {
				c.Blocks.Add(Block("image", BitmapBytes(img)));
				Surface s = dd.createFromImage(img);
				try { c.Blocks.Add(Block("surface", Read(s, out c.SrcPitch))); }
				finally { s.Dispose(); }
			}
		}

		static void ExecCreateSprite(Case c)
		{
			using (Bitmap img = SeedImage(c.Src, c.SrcSeed)) {
				c.Blocks.Add(Block("image", BitmapBytes(img)));
				Surface sprite = dd.createSprite(img);
				Surface dst = New(c.Dst);
				try {
					c.Blocks.Add(Block("sprite", Read(sprite, out c.SrcPitch)));
					Seed(dst, c.DstSeed, -1);
					byte[] before = Read(dst, out c.DstPitch);
					c.Blocks.Add(Block("dstBefore", before));
					try { dst.blt(new Point(c.Args[0], c.Args[1]), sprite); }
					catch (COMException e) { c.Error = string.Format("0x{0:x8}", e.ErrorCode); }
					int pitch;
					byte[] after = Read(dst, out pitch);
					c.Blocks.Add(Block("dstAfter", after));
					Compare(c, before, after, c.Dst[0], c.Dst[1], c.DstPitch);
				} finally { dst.Dispose(); sprite.Dispose(); }
			}
		}

		static byte[] BitmapBytes(Bitmap b)
		{
			BitmapData d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
			try {
				byte[] o = new byte[b.Width * 4 * b.Height];
				for (int y = 0; y < b.Height; y++)
					Marshal.Copy(new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), o, y * b.Width * 4, b.Width * 4);
				return o;
			} finally { b.UnlockBits(d); }
		}

		// Changed pixels and their bounds; padding (raw access only) must stay 0xA5.
		static void Compare(Case c, byte[] before, byte[] after, int w, int h, int pitch)
		{
			int n = 0, x1 = int.MaxValue, y1 = int.MaxValue, x2 = -1, y2 = -1;
			bool pad = true;
			for (int y = 0; y < h; y++) {
				for (int x = 0; x < w; x++) {
					bool diff = false;
					for (int k = 0; k < bpp; k++) if (before[y * pitch + x * bpp + k] != after[y * pitch + x * bpp + k]) diff = true;
					if (!diff) continue;
					n++;
					x1 = Math.Min(x1, x); y1 = Math.Min(y1, y); x2 = Math.Max(x2, x + 1); y2 = Math.Max(y2, y + 1);
				}
				for (int i = y * pitch + w * bpp; i < (y + 1) * pitch; i++) if (after[i] != PadByte) pad = false;
			}
			c.ChangedPixels = n;
			c.ChangedBounds = n == 0 ? null : new[] { x1, y1, x2, y2 };
			c.PaddingIntact = raw ? (pad ? "true" : "false") : "null";
		}

		static KeyValuePair<string, byte[]> Block(string name, byte[] b) { return new KeyValuePair<string, byte[]>(name, b); }

		// ---- output -------------------------------------------------------------

		static byte[] Bytes(Case c)
		{
			MemoryStream m = new MemoryStream();
			foreach (KeyValuePair<string, byte[]> b in c.Blocks) m.Write(b.Value, 0, b.Value.Length);
			return m.ToArray();
		}

		static bool Same(byte[] a, byte[] b)
		{
			if (a.Length != b.Length) return false;
			for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
			return true;
		}

		static string Sha(byte[] b)
		{
			using (SHA256Hasher h = new SHA256Hasher()) return h.Hex(b);
		}

		static string Ints(int[] v)
		{
			if (v == null) return "null";
			string[] s = new string[v.Length];
			for (int i = 0; i < v.Length; i++) s[i] = v[i].ToString();
			return "[" + string.Join(", ", s) + "]";
		}

		static string Str(string s) { return s == null ? "null" : "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\""; }

		static string Index(string label, string mode, List<Case> cases)
		{
			StringBuilder j = new StringBuilder();
			j.Append("{\n");
			j.Append("  \"provenance\": \"captured-legacy-dump\",\n");
			j.AppendFormat("  \"package\": {0},\n", Str(label));
			j.AppendFormat("  \"directDrawNetSha256\": \"{0}\",\n", FileSha(Path.Combine(Program.PackageDir, "DirectDraw.net.dll")));
			j.AppendFormat("  \"interopDxVBLibSha256\": \"{0}\",\n", FileSha(Path.Combine(Program.PackageDir, "Interop.DxVBLib.dll")));
			j.AppendFormat("  \"alphaBlendSha256\": \"{0}\",\n", AlphaBlendSha256);
			j.AppendFormat("  \"pixelMode\": \"{0}\",\n", mode);
			j.AppendFormat("  \"pixelFormat\": {{ \"bitCount\": {0}, \"rMask\": \"0x{1:x8}\", \"gMask\": \"0x{2:x8}\", \"bMask\": \"0x{3:x8}\" }},\n", bitCount, rMask, gMask, bMask);
			j.AppendFormat("  \"access\": \"{0}\",\n", raw ? "raw-lock" : "locked-pixel");
			j.Append("  \"layout\": \"<id>.bin = the case's blocks in order; a surface block is pitch*height bytes of locked memory (raw-lock) or width*bpp*height (locked-pixel), scanline padding pre-filled with 0xA5; image/bitmap blocks are 32bppArgb, width*4 per row\",\n");
			j.Append("  \"cases\": [\n");
			for (int i = 0; i < cases.Count; i++) {
				Case c = cases[i];
				j.Append("    {\n");
				j.AppendFormat("      \"id\": \"{0}\",\n", c.Id);
				j.AppendFormat("      \"op\": \"{0}\",\n", c.Op);
				j.AppendFormat("      \"dst\": {0},\n", c.Dst == null ? "null" : Ints(new[] { c.Dst[0], c.Dst[1], c.DstPitch }));
				j.AppendFormat("      \"src\": {0},\n", c.Src == null ? "null" : Ints(new[] { c.Src[0], c.Src[1], c.SrcPitch }));
				j.AppendFormat("      \"args\": {0},\n", Ints(c.Args));
				j.AppendFormat("      \"seeds\": [{0}, {1}],\n", c.DstSeed, c.SrcSeed);
				if (c.SrcKey || c.Op == "createSprite" || c.Op == "hitTest")
					j.AppendFormat("      \"colorKey\": {{ \"argb\": \"0x{0:x8}\", \"set\": {1}, \"fill\": \"0x{2:x8}\" }},\n", c.Key, c.SrcKey ? "true" : "false", ToFill(c.Key));
				if (c.Op == "fill" || c.Op == "fillRect")
					j.AppendFormat("      \"color\": {{ \"argb\": \"0x{0:x8}\", \"fill\": \"0x{1:x8}\" }},\n", c.Color, ToFill(c.Color));
				if (c.Clip != null) {
					j.AppendFormat("      \"clip\": {0},\n", Ints(c.Clip));
					j.AppendFormat("      \"resetClip\": {0},\n", c.ResetClip ? "true" : "false");
					j.AppendFormat("      \"clipEffective\": {0},\n", Ints(c.ClipEffective));
				}
				if (c.Points != null) {
					string[] pts = new string[c.Points.Length];
					for (int k = 0; k < pts.Length; k++) pts[k] = Ints(c.Points[k]);
					j.AppendFormat("      \"points\": [{0}],\n", string.Join(", ", pts));
				}
				if (c.Results != null) {
					string[] r = new string[c.Results.Length];
					for (int k = 0; k < r.Length; k++) r[k] = Str(c.Results[k]);
					j.AppendFormat("      \"results\": [{0}],\n", string.Join(", ", r));
				}
				if (c.DrawState != null)
					j.AppendFormat("      \"drawState\": {{ \"foreColor\": {0}, \"fillColor\": {1}, \"fillStyle\": {2}, \"drawWidth\": {3}, \"drawStyle\": {4} }},\n",
						c.DrawState[0], c.DrawState[1], c.DrawState[2], c.DrawState[3], c.DrawState[4]);
				j.AppendFormat("      \"error\": {0},\n", Str(c.HarnessError == null ? c.Error : "harness: " + c.HarnessError));
				string[] blocks = new string[c.Blocks.Count];
				for (int k = 0; k < blocks.Length; k++) blocks[k] = string.Format("[\"{0}\", {1}]", c.Blocks[k].Key, c.Blocks[k].Value.Length);
				j.AppendFormat("      \"blocks\": [{0}],\n", string.Join(", ", blocks));
				j.AppendFormat("      \"changedPixels\": {0},\n", c.ChangedPixels);
				j.AppendFormat("      \"changedBounds\": {0},\n", Ints(c.ChangedBounds));
				j.AppendFormat("      \"paddingIntact\": {0},\n", c.PaddingIntact);
				j.AppendFormat("      \"sourceUnchanged\": {0},\n", c.SourceUnchanged);
				j.AppendFormat("      \"sha256\": {0}\n", c.HarnessError == null ? "\"" + Sha(Bytes(c)) + "\"" : "null");
				j.Append(i + 1 < cases.Count ? "    },\n" : "    }\n");
			}
			j.Append("  ]\n}\n");
			return j.ToString();
		}

		static string FileSha(string path) { return File.Exists(path) ? Sha(File.ReadAllBytes(path)) : "absent"; }

		static string FileVersion(string path)
		{
			try { return FileVersionInfo.GetVersionInfo(path).FileVersion ?? ""; } catch { return ""; }
		}

		static string RegValue(string key, string name)
		{
			try {
				using (RegistryKey k = Registry.LocalMachine.OpenSubKey(key)) {
					object v = k == null ? null : k.GetValue(name);
					return v == null ? "absent" : v.ToString();
				}
			} catch { return "unreadable"; }
		}

		// Display adapter description: \Device\Video0 points at the driver's registry key.
		static string VideoDevice()
		{
			string p = RegValue(@"HARDWARE\DEVICEMAP\VIDEO", @"\Device\Video0");
			const string prefix = @"\Registry\Machine\";
			if (!p.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return p;
			return RegValue(p.Substring(prefix.Length), "Device Description");
		}

		// Mode-independent facts about the VM. Written once per output root; a later run
		// that sees different facts writes a side file instead of overwriting.
		static void WriteEnvironment(string outRoot, string vbox, string graphics)
		{
			StringBuilder j = new StringBuilder();
			j.Append("{\n");
			j.AppendFormat("  \"os\": {0},\n", Str(Environment.OSVersion.VersionString));
			j.AppendFormat("  \"clr\": \"{0}\",\n", Environment.Version);
			j.AppendFormat("  \"netfx35\": {0},\n", Str(RegValue(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5", "Version")));
			j.AppendFormat("  \"directX\": {0},\n", Str(RegValue(@"SOFTWARE\Microsoft\DirectX", "Version")));
			j.AppendFormat("  \"virtualBox\": {0},\n", Str(vbox));
			j.AppendFormat("  \"graphicsController\": {0},\n", Str(graphics));
			j.AppendFormat("  \"guestAdditions\": {0},\n", Str(RegValue(@"SOFTWARE\Oracle\VirtualBox Guest Additions", "Version")));
			j.AppendFormat("  \"videoDevice\": {0},\n", Str(VideoDevice()));
			j.Append("  \"modules\": [\n");
			string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
			List<string> paths = new List<string>();
			foreach (string f in new[] { "ddraw.dll", "dx7vb.dll", "dx8vb.dll", "gdi32.dll" }) paths.Add(Path.Combine(sys, f));
			// GDI+ and the CLR live outside system32; take them from the process.
			foreach (ProcessModule m in Process.GetCurrentProcess().Modules) {
				string n = m.ModuleName.ToLowerInvariant();
				if (n == "gdiplus.dll" || n == "mscorwks.dll") paths.Add(m.FileName);
			}
			for (int i = 0; i < paths.Count; i++)
				j.AppendFormat("    {{ \"path\": {0}, \"version\": {1}, \"sha256\": \"{2}\" }}{3}\n",
					Str(paths[i]), Str(FileVersion(paths[i])), FileSha(paths[i]), i + 1 < paths.Count ? "," : "");
			j.Append("  ]\n}\n");

			Directory.CreateDirectory(outRoot);
			string env = Path.Combine(outRoot, "environment.json");
			if (!File.Exists(env)) File.WriteAllText(env, j.ToString(), new UTF8Encoding(false));
			else if (File.ReadAllText(env) != j.ToString()) {
				string side = Path.Combine(outRoot, "environment-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".json");
				File.WriteAllText(side, j.ToString(), new UTF8Encoding(false));
				Console.WriteLine("  NOTE environment differs from environment.json; wrote " + side);
			}
		}
	}

	sealed class SHA256Hasher : IDisposable
	{
		readonly System.Security.Cryptography.SHA256 h = new System.Security.Cryptography.SHA256Managed();
		public string Hex(byte[] b) { return BitConverter.ToString(h.ComputeHash(b)).Replace("-", "").ToLowerInvariant(); }
		public void Dispose() { ((IDisposable)h).Dispose(); }
	}
}
