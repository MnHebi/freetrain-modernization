// Phase 2A slim-plan native-vector harness: execute the shipped
// DirectDraw.AlphaBlend.dll against fake DirectDrawSurface7 objects backed by
// heap memory, without DirectDraw, dx7vb.dll, or COM registration.
//
// Build/run with eng/native-vectors/run-probe.ps1. One process per pixel mode,
// because the DLL caches the display mode in a process-global on first call.
//
//   probe <dll> <555|565|24|32> write <dir>   regenerate vectors for one mode
//   probe <dll> <555|565|24|32> check <dir>   fail unless output equals committed vectors
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace FreeTrain.NativeVectors
{
	// Vtable-compatible redeclaration of DxVBLib.DirectDrawSurface7 (IUnknown-based,
	// 68 slots in typelib order). Only GetSurfaceDesc (37), Lock (40) and Unlock (54)
	// are called by the native routines; they take raw pointers so that the native
	// code's NULL rectangles are legal. All other slots are placeholders.
	[ComImport, Guid("9F76FDE8-8E92-11D1-8808-00C04FC2C602"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	public interface IFakeDDS7
	{
		void s00(); void s01(); void s02(); void s03(); void s04(); void s05(); void s06(); void s07(); void s08(); void s09();
		void s10(); void s11(); void s12(); void s13(); void s14(); void s15(); void s16(); void s17(); void s18(); void s19();
		void s20(); void s21(); void s22(); void s23(); void s24(); void s25(); void s26(); void s27(); void s28(); void s29();
		void s30(); void s31(); void s32(); void s33(); void s34(); void s35(); void s36();
		void GetSurfaceDesc(IntPtr desc);                        // 37
		void s38(); void s39();
		void Lock(IntPtr rect, IntPtr desc, int flags, int hnd); // 40
		void s41(); void s42(); void s43(); void s44(); void s45(); void s46(); void s47(); void s48(); void s49();
		void s50(); void s51(); void s52(); void s53();
		void Unlock(IntPtr rect);                                // 54
		void s55(); void s56(); void s57(); void s58(); void s59();
		void s60(); void s61(); void s62(); void s63(); void s64(); void s65(); void s66(); void s67();
	}

	// IAlphaBlender is dual; methods return HRESULT. The IDL declares the color
	// tables as [size_is(colorsLen)] int*, so raw pointers match the native ABI.
	[ComImport, Guid("2D16CEE2-F54C-425F-84A7-61692CF1D82C"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
	public interface IAlphaBlenderRaw
	{
		[PreserveSig] int bltAlphaFast(IntPtr dst, IntPtr src, int dx, int dy, int sx1, int sy1, int sx2, int sy2, int colorKey);
		[PreserveSig] int bltShape(IntPtr dst, IntPtr src, int dx, int dy, int sx1, int sy1, int sx2, int sy2, int fill, int colorKey);
		[PreserveSig] int bltColorTransform(IntPtr dst, IntPtr src, int dx, int dy, int sx1, int sy1, int sx2, int sy2,
			IntPtr srcColors, IntPtr dstColors, int colorsLen, int colorKey, int vflip);
	}

	public enum PixelMode { M555, M565, M24, M32 }

	[ClassInterface(ClassInterfaceType.None)]
	public sealed class FakeSurface : IFakeDDS7, IDisposable
	{
		public readonly PixelMode Mode;
		public readonly int Width, Height, Pitch, Bpp, BitCount, RMask, GMask, BMask;
		public readonly IntPtr Buffer;
		public int LockCount, UnlockCount;

		public const int Guard = 64;
		public const byte GuardByte = 0xA5;

		public FakeSurface(PixelMode mode, int width, int height, int pitchPad)
		{
			Mode = mode; Width = width; Height = height;
			switch (mode) {
			case PixelMode.M555: BitCount = 16; RMask = 31 << 10; GMask = 31 << 5; BMask = 31; break;
			case PixelMode.M565: BitCount = 16; RMask = 31 << 11; GMask = 63 << 5; BMask = 31; break;
			case PixelMode.M24:  BitCount = 24; RMask = 0xff0000; GMask = 0xff00; BMask = 0xff; break;
			default:             BitCount = 32; RMask = 0xff0000; GMask = 0xff00; BMask = 0xff; break;
			}
			Bpp = BitCount / 8;
			Pitch = width * Bpp + pitchPad;
			// Guard bytes after the last row detect overruns; padding bytes inside
			// rows use the same value so writes into padding are visible too.
			Buffer = Marshal.AllocHGlobal(Pitch * height + Guard);
			for (int i = 0; i < Pitch * height + Guard; i++) Marshal.WriteByte(Buffer, i, GuardByte);
		}

		public int Size { get { return Pitch * Height; } }

		public byte[] Pixels()
		{
			byte[] b = new byte[Size];
			Marshal.Copy(Buffer, b, 0, b.Length);
			return b;
		}

		public bool GuardIntact()
		{
			for (int i = Size; i < Size + Guard; i++) if (Marshal.ReadByte(Buffer, i) != GuardByte) return false;
			return true;
		}

		// Bytes between the last pixel of a row and the next row's start.
		public bool PaddingIntact()
		{
			for (int y = 0; y < Height; y++)
				for (int i = y * Pitch + Width * Bpp; i < (y + 1) * Pitch; i++)
					if (Marshal.ReadByte(Buffer, i) != GuardByte) return false;
			return true;
		}

		public void Set(int x, int y, int v)
		{
			for (int k = 0; k < Bpp; k++) Marshal.WriteByte(Buffer, y * Pitch + x * Bpp + k, (byte)(v >> (8 * k)));
		}

		public int Get(int x, int y)
		{
			int v = 0;
			for (int k = 0; k < Bpp; k++) v |= Marshal.ReadByte(Buffer, y * Pitch + x * Bpp + k) << (8 * k);
			return v;
		}

		void FillDesc(IntPtr desc)
		{
			DxVBLib.DDSURFACEDESC2 d = new DxVBLib.DDSURFACEDESC2();
			d.lSize = Marshal.SizeOf(typeof(DxVBLib.DDSURFACEDESC2));
			d.lWidth = Width; d.lHeight = Height; d.lPitch = Pitch;
			d.lpSurface = Buffer.ToInt32();
			d.ddpfPixelFormat.lSize = Marshal.SizeOf(typeof(DxVBLib.DDPIXELFORMAT));
			d.ddpfPixelFormat.lRGBBitCount = BitCount;
			d.ddpfPixelFormat.lRBitMask = RMask;
			d.ddpfPixelFormat.lGBitMask = GMask;
			d.ddpfPixelFormat.lBBitMask = BMask;
			Marshal.StructureToPtr(d, desc, false);
		}

		public void GetSurfaceDesc(IntPtr desc) { FillDesc(desc); }
		public void Lock(IntPtr rect, IntPtr desc, int flags, int hnd) { LockCount++; FillDesc(desc); }
		public void Unlock(IntPtr rect) { UnlockCount++; }

		public void Dispose() { Marshal.FreeHGlobal(Buffer); }

		static Exception Unused() { return new NotImplementedException("unexpected DirectDrawSurface7 slot"); }
		public void s00() { throw Unused(); } public void s01() { throw Unused(); } public void s02() { throw Unused(); } public void s03() { throw Unused(); }
		public void s04() { throw Unused(); } public void s05() { throw Unused(); } public void s06() { throw Unused(); } public void s07() { throw Unused(); }
		public void s08() { throw Unused(); } public void s09() { throw Unused(); } public void s10() { throw Unused(); } public void s11() { throw Unused(); }
		public void s12() { throw Unused(); } public void s13() { throw Unused(); } public void s14() { throw Unused(); } public void s15() { throw Unused(); }
		public void s16() { throw Unused(); } public void s17() { throw Unused(); } public void s18() { throw Unused(); } public void s19() { throw Unused(); }
		public void s20() { throw Unused(); } public void s21() { throw Unused(); } public void s22() { throw Unused(); } public void s23() { throw Unused(); }
		public void s24() { throw Unused(); } public void s25() { throw Unused(); } public void s26() { throw Unused(); } public void s27() { throw Unused(); }
		public void s28() { throw Unused(); } public void s29() { throw Unused(); } public void s30() { throw Unused(); } public void s31() { throw Unused(); }
		public void s32() { throw Unused(); } public void s33() { throw Unused(); } public void s34() { throw Unused(); } public void s35() { throw Unused(); }
		public void s36() { throw Unused(); } public void s38() { throw Unused(); } public void s39() { throw Unused(); } public void s41() { throw Unused(); }
		public void s42() { throw Unused(); } public void s43() { throw Unused(); } public void s44() { throw Unused(); } public void s45() { throw Unused(); }
		public void s46() { throw Unused(); } public void s47() { throw Unused(); } public void s48() { throw Unused(); } public void s49() { throw Unused(); }
		public void s50() { throw Unused(); } public void s51() { throw Unused(); } public void s52() { throw Unused(); } public void s53() { throw Unused(); }
		public void s55() { throw Unused(); } public void s56() { throw Unused(); } public void s57() { throw Unused(); } public void s58() { throw Unused(); }
		public void s59() { throw Unused(); } public void s60() { throw Unused(); } public void s61() { throw Unused(); } public void s62() { throw Unused(); }
		public void s63() { throw Unused(); } public void s64() { throw Unused(); } public void s65() { throw Unused(); } public void s66() { throw Unused(); }
		public void s67() { throw Unused(); }
	}

	// One executed vector: geometry, arguments, and the resulting bytes.
	sealed class VectorCase
	{
		public string Id, Op;
		public int[] Dst, Src;        // { width, height, pitchPad }; Src null for buildNightImage
		public int[] Args = new int[0];
		public int[] SrcColors, DstColors;
		public int Seed;
		public int[] Palette = new int[0];  // values injected into the source pattern
		public int Hr;
		public byte[] SrcBytes, DstBefore, DstAfter;
		public bool GuardOk, PaddingOk, SrcUnchanged, LocksBalanced;
	}

	public static class Program
	{
		[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
		static extern IntPtr LoadLibraryW(string path);
		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		static extern IntPtr GetProcAddress(IntPtr module, string name);

		[UnmanagedFunctionPointer(CallingConvention.StdCall)]
		delegate int DllGetClassObjectFn(ref Guid clsid, ref Guid iid, out IntPtr factory);
		// Plain __declspec(dllexport) functions in the native project use the default
		// MSVC __cdecl convention (no CallingConvention override in the vcproj).
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
		delegate IntPtr GetDisplayModeNameFn();
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
		delegate int BltHueTransformFn(IntPtr dst, IntPtr src, int dx, int dy, int sx1, int sy1, int sx2, int sy2,
			int r, int g, int b, int colorKey);
		[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
		delegate int BuildNightImageFn(IntPtr surface);

		[ComImport, Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
		interface IClassFactory
		{
			[PreserveSig] int CreateInstance(IntPtr outer, ref Guid iid, out IntPtr obj);
			[PreserveSig] int LockServer(bool fLock);
		}

		static readonly Guid ClsidAlphaBlender = new Guid("B6803A0F-671C-4730-A802-BB0C2C4BDAC4");
		static readonly Guid IidAlphaBlender = new Guid("2D16CEE2-F54C-425F-84A7-61692CF1D82C");

		static IAlphaBlenderRaw blender;
		static BltHueTransformFn bltHueTransform;
		static BuildNightImageFn buildNightImage;
		static PixelMode mode;

		static T Export<T>(IntPtr module, string name) where T : class
		{
			IntPtr p = GetProcAddress(module, name);
			if (p == IntPtr.Zero) throw new Exception("missing export " + name);
			return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
		}

		static bool Is16 { get { return mode == PixelMode.M555 || mode == PixelMode.M565; } }

		// GetDisplayModeName() strings (AlphaBlender.cpp) for each fake pixel format.
		static readonly Dictionary<PixelMode, string> ExpectedModeNames = new Dictionary<PixelMode, string> {
			{ PixelMode.M555, "16bit (555)" }, { PixelMode.M565, "16bit (565)" },
			{ PixelMode.M24, "24bit" }, { PixelMode.M32, "32bit" },
		};

		// Correct packing of an 8-bit RGB triple into the current pixel format.
		static int Pack(int r, int g, int b)
		{
			switch (mode) {
			case PixelMode.M555: return ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
			case PixelMode.M565: return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
			default:             return (r << 16) | (g << 8) | b;
			}
		}

		// The DLL's own RGB555/RGB565/RGB888 macros (AlphaBlender.h:28-30), used by
		// buildNightImage to recognize its special night colors. darken16 takes them
		// as WORD template arguments, so 16-bit results are truncated.
		static int DllMacro(int r, int g, int b)
		{
			switch (mode) {
			case PixelMode.M555: return (((r & 0xf8) << 8) | ((g & 0xf8) << 2) | (b >> 3)) & 0xffff;
			case PixelMode.M565: return (((r & 0xf8) << 9) | ((g & 0xfc) << 2) | (b >> 3)) & 0xffff;
			default:             return (r << 16) | (g << 8) | b;
			}
		}

		static int Key { get { return Is16 ? Pack(0, 0, 255) : Pack(255, 0, 255); } }

		// Seeded pixel pattern. Every 5th pixel is the color key and every 7th takes
		// the next palette entry, so keyed, mapped, and ordinary branches all run,
		// including mixed two-pixel DWORDs in 16-bit modes.
		static void Pattern(FakeSurface s, int seed, int key, int[] palette)
		{
			Random r = new Random(seed);
			int mask = s.Bpp == 2 ? 0xffff : 0xffffff;
			int p = 0;
			for (int y = 0; y < s.Height; y++)
				for (int x = 0; x < s.Width; x++) {
					int v = r.Next() & mask;
					int n = x + y * 3;
					if (key >= 0 && n % 5 == 0) v = key;
					else if (palette.Length > 0 && n % 7 == 0) v = palette[p++ % palette.Length];
					s.Set(x, y, v);
				}
		}

		static IntPtr Com(FakeSurface s) { return Marshal.GetComInterfaceForObject(s, typeof(IFakeDDS7)); }

		static void Execute(VectorCase c)
		{
			FakeSurface dst = new FakeSurface(mode, c.Dst[0], c.Dst[1], c.Dst[2]);
			FakeSurface src = c.Src == null ? null : new FakeSurface(mode, c.Src[0], c.Src[1], c.Src[2]);
			try {
				if (src != null) {
					Pattern(dst, c.Seed, -1, new int[0]);
					Pattern(src, c.Seed + 1, Key, c.Palette);
					c.SrcBytes = src.Pixels();
				} else {
					Pattern(dst, c.Seed, -1, c.Palette);
				}
				c.DstBefore = dst.Pixels();
				Run(c, dst, src);
				c.DstAfter = dst.Pixels();
				c.GuardOk = dst.GuardIntact() && (src == null || src.GuardIntact());
				c.PaddingOk = dst.PaddingIntact() && (src == null || src.PaddingIntact());
				c.SrcUnchanged = src == null || Same(src.Pixels(), c.SrcBytes);
				int expectedLocks = src == null ? 1 : 2;
				c.LocksBalanced = dst.LockCount + (src == null ? 0 : src.LockCount) == expectedLocks
					&& dst.UnlockCount + (src == null ? 0 : src.UnlockCount) == expectedLocks;
			} finally {
				dst.Dispose();
				if (src != null) src.Dispose();
			}
		}

		static void Run(VectorCase c, FakeSurface dst, FakeSurface src)
		{
			IntPtr pd = Com(dst), ps = src == null ? IntPtr.Zero : Com(src);
			int[] a = c.Args;
			try {
				switch (c.Op) {
				case "bltAlphaFast":
					c.Hr = blender.bltAlphaFast(pd, ps, a[0], a[1], a[2], a[3], a[4], a[5], a[6]);
					break;
				case "bltShape":
					c.Hr = blender.bltShape(pd, ps, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]);
					break;
				case "bltColorTransform":
					GCHandle hs = GCHandle.Alloc(c.SrcColors, GCHandleType.Pinned), hd = GCHandle.Alloc(c.DstColors, GCHandleType.Pinned);
					try {
						c.Hr = blender.bltColorTransform(pd, ps, a[0], a[1], a[2], a[3], a[4], a[5],
							hs.AddrOfPinnedObject(), hd.AddrOfPinnedObject(), c.SrcColors.Length, a[6], a[7]);
					} finally { hs.Free(); hd.Free(); }
					break;
				case "bltHueTransform":
					c.Hr = bltHueTransform(pd, ps, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9]);
					break;
				case "buildNightImage":
					c.Hr = buildNightImage(pd);
					break;
				default:
					throw new Exception("unknown op " + c.Op);
				}
			} finally {
				Marshal.Release(pd);
				if (ps != IntPtr.Zero) Marshal.Release(ps);
			}
		}

		// Destination/source geometries shared by the blit routines, as
		// { dstW, dstH, dstPad, srcW, srcH, srcPad, dx, dy, sx1, sy1, sx2, sy2 }.
		// Coordinates are what Surface.cs passes after managed clipping; the native
		// code clips again, which is the behavior being recorded.
		static readonly int[][] Geometries = {
			new[] { 16, 8, 0,   16, 8, 0,   0, 0,   0, 0, 16, 8 },  // aligned, even width
			new[] { 17, 9, 12,  13, 7, 4,   2, 1,   0, 0, 13, 7 },  // odd width, padded pitch
			new[] { 16, 8, 8,   12, 6, 0,  -3, -2,  0, 0, 12, 6 },  // negative destination
			new[] { 16, 8, 0,   12, 6, 0,   9, 5,   0, 0, 12, 6 },  // right/bottom overrun
			new[] { 16, 8, 0,   12, 6, 0,   1, 1,   3, 2, 10, 5 },  // source sub-rectangle
		};
		static readonly string[] GeometryNames = { "aligned", "odd-padded", "negative-dest", "overrun", "sub-rect" };

		static VectorCase Blit(string op, int g, int seed, params int[] extra)
		{
			int[] k = Geometries[g];
			VectorCase c = new VectorCase();
			c.Op = op;
			c.Id = op + "-" + GeometryNames[g];
			c.Dst = new[] { k[0], k[1], k[2] };
			c.Src = new[] { k[3], k[4], k[5] };
			c.Seed = seed;
			int[] args = new int[6 + extra.Length];
			Array.Copy(k, 6, args, 0, 6);
			Array.Copy(extra, 0, args, 6, extra.Length);
			c.Args = args;
			return c;
		}

		static List<VectorCase> BuildCases()
		{
			List<VectorCase> cases = new List<VectorCase>();
			int key = Key;
			for (int g = 0; g < Geometries.Length; g++)
				cases.Add(Blit("bltAlphaFast", g, 100 + g, key));
			for (int g = 0; g < Geometries.Length; g++)
				cases.Add(Blit("bltShape", g, 200 + g, Pack(255, 0, 0), key));

			int[] from = { Pack(0, 255, 0), Pack(255, 255, 0), Pack(128, 128, 128) };
			int[] to = { Pack(255, 0, 0), Pack(0, 0, 128), Pack(255, 255, 255) };
			foreach (int vflip in new[] { 0, -1 })
				foreach (int g in new[] { 0, 1, 2, 3, 4 }) {
					VectorCase c = Blit("bltColorTransform", g, 300 + g, key, vflip);
					c.Id += vflip == 0 ? "" : "-vflip";
					c.SrcColors = from; c.DstColors = to; c.Palette = from;
					cases.Add(c);
				}

			// Surface.bltHueTransform passes Color.ToArgb() for the three targets.
			int red = unchecked((int)0xFFFF0000), green = unchecked((int)0xFF00FF00), blue = unchecked((int)0xFF0000FF);
			int orange = unchecked((int)0xFFFF8000), teal = unchecked((int)0xFF008080), gray = unchecked((int)0xFF808080);
			for (int g = 0; g < Geometries.Length; g++)
				cases.Add(Blit("bltHueTransform", g, 400 + g, red, green, blue, key));
			VectorCase hue = Blit("bltHueTransform", 1, 450, orange, teal, gray, key);
			hue.Id += "-alt-targets";
			cases.Add(hue);

			// Night darkening rewrites the whole surface. Inject both the DLL's own
			// macro value and the correctly packed value of each special color.
			int[][] special = { new[] { 8, 0, 0 }, new[] { 0, 8, 0 }, new[] { 0, 0, 8 } };
			List<int> nightPalette = new List<int>();
			foreach (int[] s in special) { nightPalette.Add(DllMacro(s[0], s[1], s[2])); nightPalette.Add(Pack(s[0], s[1], s[2])); }
			foreach (int[] geo in new[] { new[] { 16, 8, 0 }, new[] { 17, 9, 12 } }) {
				VectorCase c = new VectorCase();
				c.Op = "buildNightImage";
				c.Id = "buildNightImage-" + (geo[2] == 0 ? "aligned" : "odd-padded");
				c.Dst = geo; c.Seed = 500 + geo[0];
				c.Palette = nightPalette.ToArray();
				cases.Add(c);
			}
			return cases;
		}

		// Characterization checks: independent restatements of rules read from the
		// native source. They pin down the harness wiring and the documented quirks;
		// the committed vectors remain the specification.
		static List<string> Characterize()
		{
			List<string> failures = new List<string>();
			int key = Key;

			if (mode == PixelMode.M32) {
				foreach (VectorCase c in BuildCasesFor("bltAlphaFast")) {
					Execute(c);
					if (!Same(Expected32Alpha(c), c.DstAfter)) failures.Add(c.Id + ": 32-bit alpha rule mismatch");
				}
			}

			if (Is16) {
				int mask = mode == PixelMode.M555 ? 0x7bde : 0xf7de;
				int t = 0xffff & ~(1 << 15) | (mode == PixelMode.M565 ? 1 << 15 : 0);  // all channel bits set
				// Quirk A: a [key, black] pair reads as one DWORD equal to the 16-bit key,
				// so the whole pair is skipped and the black pixel is not blended.
				int[] got = AlphaPair(key, 0x0000, t, t);
				if (got[0] != t || got[1] != t) failures.Add(string.Format("quirk A: [key,black] -> {0:x4},{1:x4}", got[0], got[1]));
				// Quirk B: inside a blended pair, a keyed pixel is replaced by the target
				// and then blended with itself, so it loses each channel's lowest bit.
				got = AlphaPair(key, key, t, t);
				if (got[0] != (t & mask) || got[1] != (t & mask)) failures.Add(string.Format("quirk B: [key,key] -> {0:x4},{1:x4}", got[0], got[1]));
				got = AlphaPair(0x0000, key, t, t);
				if (got[0] != ((t & mask) >> 1) || got[1] != (t & mask)) failures.Add(string.Format("quirk B: [black,key] -> {0:x4},{1:x4}", got[0], got[1]));
				// Control: the odd-width tail compares one WORD, so a lone keyed pixel is untouched.
				using (FakeSurface dst = new FakeSurface(mode, 1, 1, 0))
				using (FakeSurface src = new FakeSurface(mode, 1, 1, 0)) {
					dst.Set(0, 0, t); src.Set(0, 0, key);
					IntPtr pd = Com(dst), ps = Com(src);
					int tailHr = blender.bltAlphaFast(pd, ps, 0, 0, 0, 0, 1, 1, key);
					Marshal.Release(pd); Marshal.Release(ps);
					if (tailHr != 0) failures.Add(string.Format("control: odd tail returned 0x{0:x8}", tailHr));
					if (dst.Get(0, 0) != t) failures.Add(string.Format("control: odd tail key -> {0:x4}", dst.Get(0, 0)));
				}

				// Quirk C: buildNightImage recognizes its special colors by the DLL's own
				// RGB555/RGB565 macros, which place red/green in the wrong bits. The
				// correctly packed color is just darkened.
				int nightMask = mode == PixelMode.M555 ? 0x739C : 0xE79C;
				using (FakeSurface s = new FakeSurface(mode, 2, 1, 0)) {
					int macro = DllMacro(8, 0, 0), packed = Pack(8, 0, 0);
					s.Set(0, 0, macro); s.Set(1, 0, packed);
					IntPtr ps = Com(s);
					int nightHr = buildNightImage(ps);
					Marshal.Release(ps);
					if (nightHr != 0) failures.Add(string.Format("quirk C: buildNightImage returned 0x{0:x8}", nightHr));
					if (macro == packed) failures.Add("quirk C: macro equals packed value");
					if (s.Get(0, 0) != DllMacro(255, 8, 8)) failures.Add(string.Format("quirk C: macro (8,0,0) -> {0:x4}", s.Get(0, 0)));
					if (s.Get(1, 0) != ((packed & nightMask) >> 2)) failures.Add(string.Format("quirk C: packed (8,0,0) -> {0:x4}", s.Get(1, 0)));
				}
			}
			return failures;
		}

		static IEnumerable<VectorCase> BuildCasesFor(string op)
		{
			foreach (VectorCase c in BuildCases()) if (c.Op == op) yield return c;
		}

		// Two-pixel bltAlphaFast on a 2x1 target, returning the resulting pixels.
		static int[] AlphaPair(int s0, int s1, int t0, int t1)
		{
			using (FakeSurface dst = new FakeSurface(mode, 2, 1, 0))
			using (FakeSurface src = new FakeSurface(mode, 2, 1, 0)) {
				dst.Set(0, 0, t0); dst.Set(1, 0, t1);
				src.Set(0, 0, s0); src.Set(1, 0, s1);
				IntPtr pd = Com(dst), ps = Com(src);
				int hr = blender.bltAlphaFast(pd, ps, 0, 0, 0, 0, 2, 1, Key);
				Marshal.Release(pd); Marshal.Release(ps);
				if (hr != 0) throw new Exception("AlphaPair hr 0x" + hr.ToString("x8"));
				return new[] { dst.Get(0, 0), dst.Get(1, 0) };
			}
		}

		static byte[] Expected32Alpha(VectorCase c)
		{
			byte[] o = (byte[])c.DstBefore.Clone();
			int[] a = c.Args;
			int dPitch = c.Dst[0] * 4 + c.Dst[2], sPitch = c.Src[0] * 4 + c.Src[2];
			for (int y = 0; y < a[5] - a[3]; y++)
				for (int x = 0; x < a[4] - a[2]; x++) {
					int tx = a[0] + x, ty = a[1] + y;
					if (tx < 0 || ty < 0 || tx >= c.Dst[0] || ty >= c.Dst[1]) continue;
					uint sp = BitConverter.ToUInt32(c.SrcBytes, (a[3] + y) * sPitch + (a[2] + x) * 4);
					if ((sp & 0xffffff) == (uint)a[6]) continue;
					int off = ty * dPitch + tx * 4;
					uint tp = BitConverter.ToUInt32(o, off);
					Array.Copy(BitConverter.GetBytes(((tp & 0xfefefe) >> 1) + ((sp & 0xfefefe) >> 1)), 0, o, off, 4);
				}
			return o;
		}

		static bool Same(byte[] a, byte[] b)
		{
			if (a.Length != b.Length) return false;
			for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
			return true;
		}

		static string Sha(byte[] b)
		{
			using (var h = System.Security.Cryptography.SHA256.Create())
				return BitConverter.ToString(h.ComputeHash(b)).Replace("-", "").ToLowerInvariant();
		}

		static string Ints(int[] v)
		{
			if (v == null) return "null";
			string[] s = new string[v.Length];
			for (int i = 0; i < v.Length; i++) s[i] = v[i].ToString();
			return "[" + string.Join(", ", s) + "]";
		}

		// Vector file: src pixels (absent for buildNightImage), dst before, dst after.
		static byte[] VectorBytes(VectorCase c)
		{
			MemoryStream m = new MemoryStream();
			if (c.SrcBytes != null) m.Write(c.SrcBytes, 0, c.SrcBytes.Length);
			m.Write(c.DstBefore, 0, c.DstBefore.Length);
			m.Write(c.DstAfter, 0, c.DstAfter.Length);
			return m.ToArray();
		}

		static string Index(string modeName, List<VectorCase> cases)
		{
			StringBuilder j = new StringBuilder();
			j.Append("{\n");
			j.AppendFormat("  \"provenance\": \"native-vector\",\n");
			j.AppendFormat("  \"dll\": \"DirectDraw.AlphaBlend.dll\",\n");
			j.AppendFormat("  \"dllSha256\": \"b8153302a76f3768528453d18c9025a5017b0b5ea2350f9b3f57a8a2b37f165d\",\n");
			j.AppendFormat("  \"pixelMode\": \"{0}\",\n", modeName);
			j.AppendFormat("  \"layout\": \"<id>.bin = src pixels (omitted when src is null) + dst before + dst after; each block is pitch*height bytes, padding bytes initialized to 0xA5\",\n");
			j.Append("  \"cases\": [\n");
			for (int i = 0; i < cases.Count; i++) {
				VectorCase c = cases[i];
				j.Append("    {\n");
				j.AppendFormat("      \"id\": \"{0}\",\n", c.Id);
				j.AppendFormat("      \"op\": \"{0}\",\n", c.Op);
				j.AppendFormat("      \"dst\": {0},\n", Ints(c.Dst));
				j.AppendFormat("      \"src\": {0},\n", Ints(c.Src));
				j.AppendFormat("      \"args\": {0},\n", Ints(c.Args));
				if (c.SrcColors != null) {
					j.AppendFormat("      \"srcColors\": {0},\n", Ints(c.SrcColors));
					j.AppendFormat("      \"dstColors\": {0},\n", Ints(c.DstColors));
				}
				j.AppendFormat("      \"hresult\": \"0x{0:x8}\",\n", c.Hr);
				j.AppendFormat("      \"guardIntact\": {0},\n", c.GuardOk ? "true" : "false");
				j.AppendFormat("      \"paddingIntact\": {0},\n", c.PaddingOk ? "true" : "false");
				j.AppendFormat("      \"sourceUnchanged\": {0},\n", c.SrcUnchanged ? "true" : "false");
				j.AppendFormat("      \"locksBalanced\": {0},\n", c.LocksBalanced ? "true" : "false");
				j.AppendFormat("      \"changedBytes\": {0},\n", Changed(c.DstBefore, c.DstAfter));
				j.AppendFormat("      \"sha256\": \"{0}\"\n", Sha(VectorBytes(c)));
				j.Append(i + 1 < cases.Count ? "    },\n" : "    }\n");
			}
			j.Append("  ]\n}\n");
			return j.ToString();
		}

		static int Changed(byte[] a, byte[] b)
		{
			int n = 0;
			for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) n++;
			return n;
		}

		[STAThread]
		public static int Main(string[] args)
		{
			if (args.Length != 4 || (args[2] != "write" && args[2] != "check")) {
				Console.Error.WriteLine("usage: probe <DirectDraw.AlphaBlend.dll> <555|565|24|32> <write|check> <vector-root>");
				return 2;
			}
			if (IntPtr.Size != 4) throw new Exception("the native DLL is Win32; run as x86");
			string modeName = args[1];
			mode = (PixelMode)Enum.Parse(typeof(PixelMode), "M" + modeName);
			bool write = args[2] == "write";
			string dir = Path.Combine(args[3], modeName);

			IntPtr module = LoadLibraryW(args[0]);
			if (module == IntPtr.Zero) throw new Exception("LoadLibrary failed: " + Marshal.GetLastWin32Error());
			Guid clsid = ClsidAlphaBlender, iidFactory = typeof(IClassFactory).GUID, iid = IidAlphaBlender;
			IntPtr pf, pb;
			int hr = Export<DllGetClassObjectFn>(module, "DllGetClassObject")(ref clsid, ref iidFactory, out pf);
			if (hr != 0) throw new Exception("DllGetClassObject 0x" + hr.ToString("x8"));
			hr = ((IClassFactory)Marshal.GetObjectForIUnknown(pf)).CreateInstance(IntPtr.Zero, ref iid, out pb);
			if (hr != 0) throw new Exception("CreateInstance 0x" + hr.ToString("x8"));
			blender = (IAlphaBlenderRaw)Marshal.GetObjectForIUnknown(pb);
			bltHueTransform = Export<BltHueTransformFn>(module, "bltHueTransform");
			buildNightImage = Export<BuildNightImageFn>(module, "buildNightImage");

			List<VectorCase> cases = BuildCases();
			foreach (VectorCase c in cases) Execute(c);

			string detected = Marshal.PtrToStringAnsi(Export<GetDisplayModeNameFn>(module, "GetDisplayModeName")());
			List<string> failures = Characterize();
			if (detected != ExpectedModeNames[mode]) failures.Add(string.Format("dll detected \"{0}\", expected \"{1}\"", detected, ExpectedModeNames[mode]));
			foreach (VectorCase c in cases) {
				if (c.Hr != 0) failures.Add(string.Format("{0}: returned 0x{1:x8}", c.Id, c.Hr));
				if (!c.GuardOk) failures.Add(c.Id + ": wrote past the surface");
				if (!c.PaddingOk) failures.Add(c.Id + ": wrote into scanline padding");
				if (!c.SrcUnchanged) failures.Add(c.Id + ": modified the source surface");
				if (!c.LocksBalanced) failures.Add(c.Id + ": unbalanced Lock/Unlock");
				if (Changed(c.DstBefore, c.DstAfter) == 0) failures.Add(c.Id + ": changed no destination bytes");
			}

			string index = Index(modeName, cases);
			// Never replace the committed baseline with output from a failing run.
			if (write && failures.Count == 0) {
				Directory.CreateDirectory(dir);
				foreach (string old in Directory.GetFiles(dir, "*.bin")) File.Delete(old);
				foreach (VectorCase c in cases) File.WriteAllBytes(Path.Combine(dir, c.Id + ".bin"), VectorBytes(c));
				File.WriteAllText(Path.Combine(dir, "index.json"), index, new UTF8Encoding(false));
			} else if (!write) {
				string indexPath = Path.Combine(dir, "index.json");
				if (!File.Exists(indexPath) || File.ReadAllText(indexPath) != index) failures.Add("index.json differs from committed vectors");
				foreach (VectorCase c in cases) {
					string p = Path.Combine(dir, c.Id + ".bin");
					if (!File.Exists(p) || !Same(File.ReadAllBytes(p), VectorBytes(c))) failures.Add(c.Id + ": bytes differ from committed vector");
				}
				if (Directory.Exists(dir) && Directory.GetFiles(dir, "*.bin").Length != cases.Count) failures.Add("unexpected extra vector files");
			}

			string outcome = !write ? "checked" : failures.Count == 0 ? "written" : "NOT written (baseline left unchanged)";
			Console.WriteLine("{0}: dll mode \"{1}\", {2} cases, {3}", modeName, detected, cases.Count, outcome);
			foreach (string f in failures) Console.WriteLine("  FAIL " + f);
			return failures.Count == 0 ? 0 : 1;
		}
	}
}
