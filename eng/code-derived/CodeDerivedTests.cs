// Phase 2A item 3: code-derived characterization tests for FreeTrain r389.
//
// Runs in a 32-bit .NET Framework 4 process against the Phase 1 package's
// FreeTrain.Core.dll. No DirectDraw object is ever created: types whose static
// constructors need DirectDraw (ResourceUtil, MountainVoxel) are reached only
// through IlTransplant clones, and QuarterViewDrawer is instantiated without its
// constructor.
//
// Usage: CodeDerivedTests.exe <package-root> <check|write> <golden-root>
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.Serialization;
using System.Security.Cryptography;
using System.Text;
using System.Xml;
using org.kohsuke.directdraw;
using freetrain.controllers;
using freetrain.framework;
using freetrain.framework.graphics;
using freetrain.views;
using freetrain.world;
using freetrain.world.terrain;

[AttributeUsage(AttributeTargets.Method)]
sealed class TestAttribute : Attribute { }

sealed class AssertionException : Exception
{
    public AssertionException(string m) : base(m) { }
}

static class Program
{
    public static string PackageRoot;

    static int Main(string[] args)
    {
        if (args.Length != 3 || (args[1] != "check" && args[1] != "write"))
        {
            Console.Error.WriteLine("usage: CodeDerivedTests <package-root> <check|write> <golden-root>");
            return 2;
        }
        PackageRoot = Path.GetFullPath(args[0]);
        Golden.WriteMode = args[1] == "write";
        Golden.Root = Path.GetFullPath(args[2]);
        AppDomain.CurrentDomain.AssemblyResolve += delegate (object s, ResolveEventArgs e)
        {
            string p = Path.Combine(PackageRoot, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };
        if (IntPtr.Size != 4) { Console.Error.WriteLine("must run as x86"); return 2; }
        return Runner.Run();
    }
}

static class Runner
{
    public static int Run()
    {
        int passed = 0, failed = 0;
        List<string> names = new List<string>();
        foreach (Type t in typeof(Runner).Assembly.GetTypes())
        {
            foreach (MethodInfo m in t.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
            {
                if (m.GetCustomAttributes(typeof(TestAttribute), false).Length == 0) continue;
                string name = t.Name + "." + m.Name;
                names.Add(name);
                try
                {
                    Fixtures.Reset();
                    m.Invoke(null, null);
                    passed++;
                    Console.WriteLine("PASS " + name);
                }
                catch (TargetInvocationException e)
                {
                    failed++;
                    Console.WriteLine("FAIL " + name + ": " + e.InnerException);
                }
            }
        }
        try
        {
            Inventory(names);
            Console.WriteLine("PASS inventory (" + names.Count + " tests, " + Golden.Checked.Count + " golden files, Core hash)");
        }
        catch (AssertionException e)
        {
            failed++;
            Console.WriteLine("FAIL inventory: " + e.Message);
        }
        Console.WriteLine("{0} passed, {1} failed", passed, failed);
        if (failed != 0) return 1;
        if (Golden.WriteMode)
        {
            Golden.Flush();
            Console.WriteLine("wrote {0} golden files to {1}", Golden.Pending.Count, Golden.Root);
        }
        return 0;
    }

    /// <summary>
    /// Pins the corpus: the discovered test set must equal tests.txt (a test that loses
    /// its [Test] attribute fails here instead of vanishing), the package's
    /// FreeTrain.Core.dll must be the one the goldens were written from, and every
    /// golden file must have been consumed by some test.
    /// </summary>
    static void Inventory(List<string> names)
    {
        names.Sort(StringComparer.Ordinal);
        string list = Path.Combine(Golden.Root, "tests.txt");
        if (!Golden.WriteMode && File.Exists(list))
        {
            List<string> pinnedTests = new List<string>(File.ReadAllText(list).TrimEnd('\n').Split('\n'));
            List<string> missing = pinnedTests.FindAll(delegate (string n) { return !names.Contains(n); });
            List<string> extra = names.FindAll(delegate (string n) { return !pinnedTests.Contains(n); });
            if (missing.Count + extra.Count > 0)
                throw new AssertionException("test set differs from tests.txt: missing [" + string.Join(", ", missing.ToArray()) +
                    "], unexpected [" + string.Join(", ", extra.ToArray()) + "]");
        }
        Golden.Check("tests", names);

        string core = Path.Combine(Program.PackageRoot, "FreeTrain.Core.dll");
        string hash;
        using (SHA256 sha = SHA256.Create())
        using (FileStream fs = File.OpenRead(core))
            hash = BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
        string[] provenance = { "FreeTrain.Core.dll sha256 " + hash };
        if (!Golden.WriteMode)
        {
            string path = Path.Combine(Golden.Root, "provenance.txt");
            string pinned = File.Exists(path) ? File.ReadAllText(path).TrimEnd('\n') : "(missing)";
            if (pinned != provenance[0])
                throw new AssertionException("goldens were written from <" + pinned + "> but the package has <" + provenance[0] +
                    ">. Rebuild the pinned package, or regenerate with -Action Write and review the golden diff.");
        }
        Golden.Check("provenance", provenance);

        if (!Golden.WriteMode)
            foreach (string f in Directory.GetFiles(Golden.Root, "*.txt"))
                if (!Golden.Checked.Contains(Path.GetFileNameWithoutExtension(f)))
                    throw new AssertionException("golden file " + Path.GetFileName(f) + " is not checked by any test");
    }
}

static class Assert
{
    public static void Eq<T>(T expected, T actual, string what)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new AssertionException(what + ": expected <" + expected + "> but was <" + actual + ">");
    }

    public static void True(bool c, string what) { if (!c) throw new AssertionException(what); }

    public static void Lines(IList<string> expected, IList<string> actual, string what)
    {
        int n = Math.Min(expected.Count, actual.Count);
        for (int i = 0; i < n; i++)
            if (expected[i] != actual[i])
                throw new AssertionException(what + ": first difference at #" + i + ": expected <" + expected[i] + "> but was <" + actual[i] + ">");
        Eq(expected.Count, actual.Count, what + " (count)");
    }

    public static T Throws<T>(Action a, string what) where T : Exception
    {
        try { a(); }
        catch (T e) { return e; }
        throw new AssertionException(what + ": expected " + typeof(T).Name);
    }
}

/// <summary>Shared world/state setup and reflection helpers.</summary>
static class Fixtures
{
    const BindingFlags Any = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;

    public static void Reset()
    {
        Recorder.Log.Clear();
        World.world = null;
    }

    /// <summary>
    /// A world from the private "temporary" constructor (the one CreatePreviewWorld uses):
    /// no plug-ins, trains, clock handlers, or land-value engine.
    /// </summary>
    public static World NewWorld(int h, int v, int d, int waterLevel)
    {
        ConstructorInfo c = typeof(World).GetConstructor(BindingFlags.NonPublic | BindingFlags.Instance, null,
            new Type[] { typeof(Distance), typeof(int), typeof(bool) }, null);
        World w = (World)c.Invoke(new object[] { new Distance(h, v, d), waterLevel, true });
        World.world = w;
        return w;
    }

    public static Time NewTime(long minutes)
    {
        ConstructorInfo c = typeof(Time).GetConstructor(BindingFlags.NonPublic | BindingFlags.Instance, null,
            new Type[] { typeof(long) }, null);
        return (Time)c.Invoke(new object[] { minutes });
    }

    public static void SetClock(World w, long minutes) { SetField(w.clock, "currentTime", minutes); }

    public static void SetNightMode(World w, NightSpriteMode m) { SetField(w.viewOptions, "_nightSpriteMode", m); }

    public static QuarterViewDrawer NewDrawer(World w, Point topLeft, int heightCut)
    {
        QuarterViewDrawer d = (QuarterViewDrawer)FormatterServices.GetUninitializedObject(typeof(QuarterViewDrawer));
        SetField(d, "world", w);
        SetField(d, "topLeft", topLeft);
        SetField(d, "_heightCutHeight", heightCut);
        return d;
    }

    public static FieldInfo Field(Type t, string name)
    {
        for (; t != null; t = t.BaseType)
        {
            FieldInfo f = t.GetField(name, Any | BindingFlags.DeclaredOnly);
            if (f != null) return f;
        }
        throw new MissingFieldException(name);
    }

    public static void SetField(object o, string name, object value) { Field(o.GetType(), name).SetValue(o, value); }
    public static object GetField(object o, string name) { return Field(o.GetType(), name).GetValue(o); }

    public static MethodInfo Method(Type t, string name, params Type[] ps)
    {
        MethodInfo m = t.GetMethod(name, Any, null, ps, null);
        if (m == null) throw new MissingMethodException(t.Name, name);
        return m;
    }

    public static MethodInfo Getter(Type t, string prop)
    {
        return t.GetProperty(prop, Any).GetGetMethod(true);
    }

    public static string P(Point p) { return p.X + "," + p.Y; }
}

/// <summary>Event log written by the test doubles.</summary>
static class Recorder
{
    public static readonly List<string> Log = new List<string>();
}

sealed class RecordingSprite : Sprite
{
    readonly string name;
    public RecordingSprite(string n) { name = n; }
    public void draw(Surface surface, Point pt) { Recorder.Log.Add(name + "@" + Fixtures.P(pt)); }
    public void drawShape(Surface surface, Point pt, Color color)
    {
        Recorder.Log.Add(name + ".shape@" + Fixtures.P(pt) + " #" + (color.ToArgb() & 0xffffff).ToString("X6"));
    }
    public void drawAlpha(Surface surface, Point pt) { Recorder.Log.Add(name + ".alpha@" + Fixtures.P(pt)); }
    public Size size { get { return new Size(32, 16); } }
    public Point offset { get { return Point.Empty; } }
    public bool HitTest(int x, int y) { return false; }
    public override string ToString() { return name; }
}

class RecordingVoxel : Voxel
{
    readonly Location loc;
    public RecordingVoxel(Location l) { loc = l; }
    public override Location location { get { return loc; } }
    public override Entity entity { get { return null; } }
    public override void draw(DrawContext display, Point pt, int heightCutDiff)
    {
        Recorder.Log.Add("voxel(" + loc.x + "," + loc.y + "," + loc.z + ")@" + Fixtures.P(pt) + " cut=" + heightCutDiff);
    }
    public override void setFence(Direction d, Fence f) { }
    public override Fence getFence(Direction d) { return null; }
    protected override void drawFrontFence(DrawContext display, Point pt) { }
    protected override void drawBehindFence(DrawContext display, Point pt) { }
}

sealed class TransparentVoxel : RecordingVoxel
{
    public TransparentVoxel(Location l) : base(l) { }
    public override bool transparent { get { return true; } }
}

sealed class HoleRecordingVoxel : RecordingVoxel, HoleVoxel
{
    readonly bool allowAbove, allowBelow;
    public HoleRecordingVoxel(Location l, bool above, bool below) : base(l) { allowAbove = above; allowBelow = below; }
    public bool drawGround(bool above)
    {
        Recorder.Log.Add("drawGround(above=" + above + ") at " + location);
        return above ? allowAbove : allowBelow;
    }
}

/// <summary>Replacement targets for IlTransplant substitutions.</summary>
public static class Seams
{
    public static readonly Sprite Ground = new RecordingSprite("ground");
    public static readonly Sprite WinterGround = new RecordingSprite("winterGround");
    public static readonly Sprite UnderWater = new RecordingSprite("underWater");
    public static readonly Sprite UnderGround = new RecordingSprite("underGround");
    static readonly Sprite[] groundChips = new Sprite[] { Ground, WinterGround };
    static readonly GlobalOptions options = (GlobalOptions)FormatterServices.GetUninitializedObject(typeof(GlobalOptions));

    public static Color[][] MountainColors;
    public static Color[] WaterColors;

    public static Sprite[] GroundChips() { return groundChips; }
    public static Sprite UnderWaterChip() { return UnderWater; }
    public static Sprite UnderGroundChip() { return UnderGround; }
    public static GlobalOptions Options() { return options; }
    public static void SetClipRect(Surface s, Rectangle r) { Recorder.Log.Add("clip " + r.X + "," + r.Y + " " + r.Width + "x" + r.Height); }
    public static Surface NoSurface(DrawContext dc) { return null; }
    public static MainWindow NoMainWindow() { return null; }
    public static ModalController NoController(MainWindow w) { return null; }
    public static Color[][] GetMountainColors() { return MountainColors; }
    public static Color[] GetWaterColors() { return WaterColors; }
    public static Location StandInLocation(object v) { return ((MountainStandIn)v).Location; }
    public static int StandInHeight(object v, int idx) { return ((MountainStandIn)v).Heights[idx]; }
}

/// <summary>Receiver for MountainVoxel clones. Heights are indexed like getHeight(int): 0=NE, 1=SE, 2=SW, 3=NW.</summary>
public sealed class MountainStandIn
{
    public Location Location;
    public readonly int[] Heights = new int[4];
}

/// <summary>Builds the clones once; members are compared by metadata identity.</summary>
static class Clones
{
    sealed class MemberComparer : IEqualityComparer<MemberInfo>
    {
        public bool Equals(MemberInfo a, MemberInfo b) { return a.Module == b.Module && a.MetadataToken == b.MetadataToken; }
        public int GetHashCode(MemberInfo m) { return m.MetadataToken; }
    }

    static Dictionary<MemberInfo, MethodInfo> Subs() { return new Dictionary<MemberInfo, MethodInfo>(new MemberComparer()); }
    static MethodInfo S(string name) { return typeof(Seams).GetMethod(name); }

    static DynamicMethod groundChip, draw, tick, loadColors, fromHsv, currentMountainColors, selectColor;

    /// <summary>ResourceUtil.getGroundChip(World) with groundChips redirected.</summary>
    public static DynamicMethod GetGroundChip()
    {
        if (groundChip == null)
        {
            var subs = Subs();
            subs[Fixtures.Field(typeof(ResourceUtil), "groundChips")] = S("GroundChips");
            groundChip = IlTransplant.Clone(Fixtures.Method(typeof(ResourceUtil), "getGroundChip", typeof(World)), subs);
        }
        return groundChip;
    }

    /// <summary>
    /// QuarterViewDrawer.draw(Rectangle, MapOverlay) with the offscreen surface, the
    /// ResourceUtil chips, and Core.options redirected. Everything else, including
    /// shouldDrawGround, the coordinate helpers, World, and Voxel.drawVoxel, is shipped code.
    /// </summary>
    public static DynamicMethod Draw()
    {
        if (draw == null)
        {
            var subs = Subs();
            subs[typeof(Surface).GetProperty("clipRect").GetSetMethod()] = S("SetClipRect");
            subs[Fixtures.Getter(typeof(DrawContext), "surface")] = S("NoSurface");
            subs[Fixtures.Method(typeof(ResourceUtil), "getGroundChip", typeof(World))] = GetGroundChip();
            subs[Fixtures.Field(typeof(ResourceUtil), "underWaterChip")] = S("UnderWaterChip");
            subs[Fixtures.Field(typeof(ResourceUtil), "underGroundChip")] = S("UnderGroundChip");
            subs[Fixtures.Field(typeof(Core), "options")] = S("Options");
            draw = IlTransplant.Clone(Fixtures.Method(typeof(QuarterViewDrawer), "draw", typeof(Rectangle), typeof(MapOverlay)), subs);
        }
        return draw;
    }

    /// <summary>Clock.tick() with MainWindow.mainWindow.currentController forced to null.</summary>
    public static DynamicMethod Tick()
    {
        if (tick == null)
        {
            var subs = Subs();
            subs[Fixtures.Field(typeof(MainWindow), "mainWindow")] = S("NoMainWindow");
            subs[Fixtures.Getter(typeof(MainWindow), "currentController")] = S("NoController");
            tick = IlTransplant.Clone(Fixtures.Method(typeof(Clock), "tick"), subs);
        }
        return tick;
    }

    public static DynamicMethod FromHsv()
    {
        if (fromHsv == null)
            fromHsv = IlTransplant.Clone(Fixtures.Method(typeof(MountainVoxel), "fromHSV", typeof(int), typeof(int), typeof(int)), null);
        return fromHsv;
    }

    public static DynamicMethod LoadColors()
    {
        if (loadColors == null)
        {
            var subs = Subs();
            subs[Fixtures.Method(typeof(MountainVoxel), "fromHSV", typeof(int), typeof(int), typeof(int))] = FromHsv();
            loadColors = IlTransplant.Clone(Fixtures.Method(typeof(MountainVoxel), "loadColors", typeof(XmlElement)), subs);
        }
        return loadColors;
    }

    public static DynamicMethod CurrentMountainColors()
    {
        if (currentMountainColors == null)
        {
            var subs = Subs();
            subs[Fixtures.Field(typeof(MountainVoxel), "mountainColors")] = S("GetMountainColors");
            currentMountainColors = IlTransplant.Clone(Fixtures.Getter(typeof(MountainVoxel), "currentMountainColors"), subs);
        }
        return currentMountainColors;
    }

    /// <summary>
    /// MountainVoxel.selectColor() on a <see cref="MountainStandIn"/> receiver: allocating a
    /// MountainVoxel runs its static constructor, which needs DirectDraw. The receiver is
    /// reached only through Voxel.location and getHeight(int), both redirected; isUnderWater,
    /// currentMountainColors, and mapColor are cloned shipped bodies.
    /// </summary>
    public static DynamicMethod SelectColor()
    {
        if (selectColor == null)
        {
            Type mv = typeof(MountainVoxel);
            var colorsSubs = Subs();
            colorsSubs[Fixtures.Field(mv, "mountainColors")] = S("GetMountainColors");
            var waterSubs = Subs();
            waterSubs[Fixtures.Getter(typeof(Voxel), "location")] = S("StandInLocation");

            var subs = Subs();
            subs[Fixtures.Getter(mv, "currentMountainColors")] = IlTransplant.Clone(Fixtures.Getter(mv, "currentMountainColors"), colorsSubs, typeof(object));
            subs[Fixtures.Getter(mv, "isUnderWater")] = IlTransplant.Clone(Fixtures.Getter(mv, "isUnderWater"), waterSubs, typeof(object));
            // mapColor never touches its receiver, so it needs no substitution.
            subs[Fixtures.Method(mv, "mapColor", typeof(Color))] = IlTransplant.Clone(Fixtures.Method(mv, "mapColor", typeof(Color)), null, typeof(object));
            subs[Fixtures.Method(mv, "getHeight", typeof(int))] = S("StandInHeight");
            subs[Fixtures.Field(mv, "waterColors")] = S("GetWaterColors");
            selectColor = IlTransplant.Clone(Fixtures.Method(mv, "selectColor"), subs, typeof(object));
        }
        return selectColor;
    }
}
