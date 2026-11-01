using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;
using System.Xml;
using freetrain.controllers;
using freetrain.framework.graphics;
using freetrain.views;
using freetrain.views.map;
using freetrain.world;
using freetrain.world.terrain;

/// <summary>
/// Golden files under fixtures/code-derived/. Check mode fails on any difference;
/// Write mode replaces them (the runner refuses to write when a hand assertion fails).
/// </summary>
static class Golden
{
    public static string Root;
    public static bool WriteMode;
    public static readonly Dictionary<string, List<string>> Pending = new Dictionary<string, List<string>>();

    public static void Check(string name, IList<string> lines)
    {
        if (WriteMode) { Pending[name] = new List<string>(lines); return; }
        string path = Path.Combine(Root, name + ".txt");
        if (!File.Exists(path)) throw new AssertionException("missing golden " + path + " (run with -Action Write)");
        string text = File.ReadAllText(path);
        List<string> expected = new List<string>(text.TrimEnd('\n').Split('\n'));
        Assert.Lines(expected, lines, "golden " + name);
    }

    public static void Flush()
    {
        Directory.CreateDirectory(Root);
        foreach (KeyValuePair<string, List<string>> e in Pending)
            File.WriteAllText(Path.Combine(Root, e.Key + ".txt"), string.Join("\n", e.Value.ToArray()) + "\n", new UTF8Encoding(false));
    }
}

static class CoordinateTests
{
    // Width 8 (H), depth 16 (V), height 5. (size.y-1)/2 = 7 is the x origin.
    static World W() { return Fixtures.NewWorld(8, 16, 5, 0); }

    [Test]
    static void FromXYZToAB_FixedProjection()
    {
        World w = W();
        Assert.Eq(new Point(0, 0), w.fromXYZToAB(7, 0, 0), "origin column x=(size.y-1)/2");
        Assert.Eq(new Point(16, -8), w.fromXYZToAB(8, 0, 0), "+x");
        Assert.Eq(new Point(16, 8), w.fromXYZToAB(7, 1, 0), "+y");
        Assert.Eq(new Point(0, -16), w.fromXYZToAB(7, 0, 1), "+z is 16 px up");
        Assert.Eq(w.fromXYZToAB(8, -1, 0), w.fromXYZToAB(7, 0, 1), "z collapses onto (x+1,y-1)");
        Assert.Eq(new Rectangle(16, -24, 32, 32), w.getBoundingBox(new Location(8, 0, 0)), "bounding box is AB top-left minus 16 px, 32x32");
    }

    [Test]
    static void FromXYZToAB_UsesStaticWorldNotReceiver()
    {
        World a = Fixtures.NewWorld(8, 16, 5, 0);
        World b = Fixtures.NewWorld(8, 4, 5, 0);   // World.world = b, origin (4-1)/2 = 1
        Assert.Eq(new Point(0, 0), a.fromXYZToAB(1, 0, 0), "receiver's size is ignored; World.world.size.y is used");
        Assert.True(b == World.world, "setup");
    }

    [Test]
    static void HV_RoundTripAndIndexer()
    {
        World w = W();
        for (int v = 0; v < 16; v++)
            for (int h = 0; h < 8; h++)
            {
                Location l = w.toXYZ(h, v, 2);
                int hh, vv;
                w.toHV(l, out hh, out vv);
                Assert.Eq(h + "," + v, hh + "," + vv, "toHV(toXYZ)");
                Assert.True(w.isInsideWorld(l), "inside " + l);
                Voxel vx = new RecordingVoxel(l);
                w[l] = vx;
                Assert.True(w.voxelHVD(h, v, 2) == vx, "indexer stores at (h,v)");
            }
        Assert.True(w[w.toXYZ(0, 0, 2).x - 1, w.toXYZ(0, 0, 2).y, 2] is World.OutOfWorldVoxel, "outside returns OutOfWorldVoxel");
        Assert.True(w[new Location(7, 0, 0)] == null, "empty inside returns null");
    }

    [Test]
    static void InsideAndBorderTable()
    {
        World w = W();
        List<string> lines = new List<string>();
        for (int y = -2; y < 14; y++)
        {
            StringBuilder sb = new StringBuilder();
            for (int x = -2; x < 20; x++)
            {
                Location l = new Location(x, y, 1);
                bool inside = w.isInsideWorld(l), border = w.isBorderOfWorld(l);
                sb.Append(inside ? (border ? 'b' : 'I') : (border ? '.' : '?'));
            }
            lines.Add("y=" + y + " " + sb);
        }
        Golden.Check("world-inside-border-z1", lines);
    }

    [Test]
    static void DrawerClientConversions()
    {
        World w = W();
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(100, -40), 4);
        Assert.Eq(new Point(-90, 45), d.fromABToClient(10, 5), "AB->client subtracts topLeft");
        Assert.Eq(new Point(10, 5), d.fromClientToAB(-90, 45), "client->AB adds topLeft");
        Assert.Eq(new Rectangle(-90, 45, 7, 9), d.fromABToClient(new Rectangle(10, 5, 7, 9)), "rect keeps size");

        for (int z = 0; z < 5; z++)
            for (int v = 0; v < 16; v++)
                for (int h = 0; h < 8; h++)
                    Assert.Eq(d.fromXYZToClient(w.toXYZ(h, v, z)), d.fromHVZToClient(h, v, z), "HVZ and XYZ paths agree at " + h + "," + v + "," + z);

        Assert.Eq(new Point(16 * (2 * 3 + 1) - 100, 8 * 5 + 40), d.fromHVZToClient(3, 5, 0), "odd row shifts 16 px");
        Assert.Eq(d.fromHVZToClient(3, 5, 0) - new Size(0, 16), d.fromHVZToClient(3, 5, 1), "z step = 16 px up, same column parity");
    }

    [Test]
    static void FromABToHV_Truncation()
    {
        World w = W();
        QuarterViewDrawer d = Fixtures.NewDrawer(w, Point.Empty, 4);
        System.Reflection.MethodInfo m = Fixtures.Method(typeof(QuarterViewDrawer), "fromABToHV", typeof(Rectangle));
        List<string> lines = new List<string>();
        Rectangle[] cases = {
            new Rectangle(0, 0, 64, 32), new Rectangle(15, 7, 1, 1), new Rectangle(16, 8, 1, 1),
            new Rectangle(-15, -7, 30, 14), new Rectangle(-16, -8, 32, 16), new Rectangle(-50, -20, 10, 10),
            new Rectangle(33, 17, 100, 50), new Rectangle(0, 0, 0, 0)
        };
        foreach (Rectangle r in cases)
        {
            Rectangle hv = (Rectangle)m.Invoke(d, new object[] { r });
            lines.Add(string.Format("AB({0},{1},{2},{3}) -> H[{4}..{5}] V[{6}..{7}]",
                r.X, r.Y, r.Width, r.Height, hv.Left, hv.Right, hv.Top, hv.Bottom));
        }
        Golden.Check("drawer-ab-to-hv", lines);
    }

    [Test]
    static void FromABToXYZ_HitMaskWithoutController()
    {
        World w = W();
        QuarterViewDrawer d = Fixtures.NewDrawer(w, Point.Empty, 4);
        // Every in-world (x,y): which pixels of its 32x16 AB footprint pick it back?
        for (int v = 0; v < 16; v++)
            for (int h = 0; h < 8; h++)
            {
                Location l = w.toXYZ(h, v, 0);
                Point ab = w.fromXYZToAB(l);
                for (int dy = 0; dy < 16; dy++)
                    for (int dx = 0; dx < 32; dx++)
                    {
                        bool hit = d.fromABToXYZ(ab.X + dx, ab.Y + dy, null) == l;
                        // half-open diamond: -16 <= dx-2dy < 16 and 16 <= dx+2dy < 48
                        bool rule = -16 <= dx - 2 * dy && dx - 2 * dy < 16 && 16 <= dx + 2 * dy && dx + 2 * dy < 48;
                        Assert.Eq(rule, hit, "hit at " + l + " +" + dx + "," + dy);
                    }
            }
        Point o = w.fromXYZToAB(9, 4, 0);
        Assert.Eq(new Location(9, 4, 0), d.fromABToXYZ(o.X + 16, o.Y + 8, null), "diamond centre");
        Assert.Eq(new Location(10, 4, 0), d.fromABToXYZ(o.X + 16, o.Y, null), "top vertex belongs to +x neighbour");
    }

    sealed class Probe : ModalController, LocationDisambiguator
    {
        public readonly List<string> probes = new List<string>();
        readonly Location accept;
        public Probe(Location a) { accept = a; }
        public bool isSelectable(Location loc) { probes.Add(loc.x + "," + loc.y + "," + loc.z); return loc == accept; }
        public void onClick(MapViewWindow source, Location loc, Point ab) { }
        public void onRightClick(MapViewWindow source, Location loc, Point ab) { }
        public void onMouseMove(MapViewWindow source, Location loc, Point ab) { }
        public void onAttached() { }
        public void onDetached() { }
        public string name { get { return "probe"; } }
        public LocationDisambiguator disambiguator { get { return this; } }
        public MapOverlay overlay { get { return null; } }
    }

    [Test]
    static void FromABToXYZ_DisambiguationOrder()
    {
        World w = W();
        QuarterViewDrawer d = Fixtures.NewDrawer(w, Point.Empty, 3);
        Point ab = w.fromXYZToAB(9, 4, 0) + new Size(16, 8);
        Probe p = new Probe(new Location(8, 5, 1));
        Assert.Eq(new Location(8, 5, 1), d.fromABToXYZ(ab.X, ab.Y, p), "first selectable from the height cut down");
        Assert.Eq("6,7,3|7,6,2|8,5,1", string.Join("|", p.probes.ToArray()), "probe order z=heightCut..0 at (x-z,y+z,z)");
        Probe none = new Probe(Location.UNPLACED);
        Assert.Eq(new Location(9, 4, 0), d.fromABToXYZ(ab.X, ab.Y, none), "nothing selectable falls back to z=0");
        Assert.Eq(4, none.probes.Count, "probes heightCut+1 levels");
    }

}

static class TraversalTests
{
    static List<string> Draw(QuarterViewDrawer d, Rectangle ab)
    {
        Recorder.Log.Clear();
        IlTransplant.Invoke(Clones.Draw(), d, ab, null);
        return new List<string>(Recorder.Log);
    }

    [Test]
    static void FlatDayOrder()
    {
        World w = Fixtures.NewWorld(3, 6, 3, 0);
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(0, 0), 2);
        List<string> log = Draw(d, new Rectangle(0, 0, 64, 24));
        Assert.Eq("clip 0,0 64x24", log[0], "clip is the client rect");
        Golden.Check("draw-flat-day", log);
    }

    [Test]
    static void TraversalIsVMajorHMinorZAscending()
    {
        World w = Fixtures.NewWorld(4, 8, 4, 0);
        // voxel at every (h,v,z) above ground
        for (int v = 0; v < 8; v++)
            for (int h = 0; h < 4; h++)
                for (int z = 1; z < 4; z++)
                    w[w.toXYZ(h, v, z)] = new RecordingVoxel(w.toXYZ(h, v, z));
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(0, -48), 3);
        List<string> log = Draw(d, new Rectangle(0, -48, 128, 112));
        List<string> expected = new List<string>();
        expected.Add("clip 0,0 128x112");
        // fromABToHV: H[0..4] V[-7..8], capped to the world; Vmax = min(8+2*3, 7)
        for (int v = 0; v <= 7; v++)
            for (int h = 0; h <= 3; h++)
                for (int z = 0; z <= 3; z++)
                {
                    Point pt = d.fromHVZToClient(h, v, z);
                    if (z == 0) expected.Add("ground@" + Fixtures.P(pt));
                    else
                    {
                        Location l = w.toXYZ(h, v, z);
                        expected.Add("voxel(" + l.x + "," + l.y + "," + l.z + ")@" + Fixtures.P(pt) + " cut=-1");
                    }
                }
        Assert.Lines(expected, log, "order");
    }

    [Test]
    static void WaterSurfaceDayAndNight()
    {
        World w = Fixtures.NewWorld(3, 6, 4, 2);       // ground levels start at the water level
        w.lowerGround(w.toXYZ(1, 2, 0).x, w.toXYZ(1, 2, 0).y);
        w.lowerGround(w.toXYZ(1, 2, 0).x, w.toXYZ(1, 2, 0).y);   // (1,2) ground 0, under water
        w.lowerGround(w.toXYZ(2, 2, 0).x, w.toXYZ(2, 2, 0).y);   // (2,2) ground 1
        w.raiseGround(w.toXYZ(0, 2, 0).x, w.toXYZ(0, 2, 0).y);   // (0,2) ground 3
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(0, -32), 3);
        Rectangle r = new Rectangle(0, -32, 96, 64);
        Golden.Check("draw-water-day", Draw(d, r));
        Fixtures.SetNightMode(w, NightSpriteMode.AlwaysNight);
        List<string> night = Draw(d, r);
        Assert.True(night.Exists(delegate (string s) { return s.Contains(".shape@") && s.EndsWith("#001C2F"); }), "night water = ColorMap.getNightColor(0,114,188)");
        Golden.Check("draw-water-night", night);
    }

    [Test]
    static void HeightCut()
    {
        World w = Fixtures.NewWorld(3, 6, 5, 1);
        Location a = w.toXYZ(1, 2, 0);
        for (int i = 0; i < 3; i++) w.raiseGround(a.x, a.y);    // ground 4
        w.lowerGround(w.toXYZ(2, 3, 0).x, w.toXYZ(2, 3, 0).y);   // ground 0, under water
        for (int z = 0; z < 5; z++) w[w.toXYZ(0, 3, z)] = new RecordingVoxel(w.toXYZ(0, 3, z));
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(0, -32), 2);   // cut below the top (4)
        Golden.Check("draw-height-cut-2", Draw(d, new Rectangle(0, -32, 96, 64)));
    }

    [Test]
    static void TransparentAndHoleVoxels()
    {
        World w = Fixtures.NewWorld(3, 6, 4, 1);
        Location t = w.toXYZ(0, 2, 1);
        w[t] = new TransparentVoxel(t);                              // transparent: ground still drawn
        Location hole = w.toXYZ(1, 2, 1);
        w[hole] = new HoleRecordingVoxel(hole, true, false);         // cell above the surface; queried with above=false
        Location below = w.toXYZ(1, 2, 0);
        w[below] = new RecordingVoxel(below);                        // reached only because z starts one lower
        Location hole2 = w.toXYZ(2, 2, 0);
        w[hole2] = new HoleRecordingVoxel(hole2, false, true);       // cell below the surface; queried with above=true
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(0, -32), 3);
        List<string> log = Draw(d, new Rectangle(0, -32, 96, 64));
        Assert.True(log.Contains("drawGround(above=False) at " + hole) && log.Contains("drawGround(above=True) at " + hole2),
            "argument is inverted relative to the HoleVoxel doc comment");
        Assert.True(!log.Contains("ground@" + Fixtures.P(d.fromHVZToClient(1, 2, 1))) && !log.Contains("ground@" + Fixtures.P(d.fromHVZToClient(2, 2, 1))),
            "both ground chips suppressed");
        Assert.True(log.Contains("voxel(" + below.x + "," + below.y + ",0)@" + Fixtures.P(d.fromHVZToClient(1, 2, 0)) + " cut=-1"),
            "voxel below a cut surface is drawn");
        Golden.Check("draw-transparent-hole", log);
    }

    [Test]
    static void WinterGroundChip()
    {
        World w = Fixtures.NewWorld(2, 4, 2, 0);
        Fixtures.SetClock(w, 10 * Time.DAY + 12 * Time.HOUR);   // January 11
        QuarterViewDrawer d = Fixtures.NewDrawer(w, Point.Empty, 1);
        List<string> log = Draw(d, new Rectangle(0, 0, 32, 16));
        Assert.True(log.Count > 1 && log.TrueForAll(delegate (string s) { return s.StartsWith("clip") || s.StartsWith("winterGround@"); }), "winter uses groundChips[1]");
    }

    [Test]
    static void NegativeLeftEdgeThrows()
    {
        World w = Fixtures.NewWorld(3, 6, 3, 0);
        QuarterViewDrawer d = Fixtures.NewDrawer(w, new Point(-64, 0), 2);
        // h is not clamped at 0 (only v is); (left-16)/32 truncates toward zero, so left >= -15 still starts at h=0.
        Draw(d, new Rectangle(-15, 0, 32, 16));
        Assert.Throws<IndexOutOfRangeException>(delegate { Draw(d, new Rectangle(-16, 0, 32, 16)); }, "left <= -16 indexes groundLevels[-1,..]");
    }
}

sealed class CountingListener : VoxelOutlookListener
{
    public int all;
    public void onUpdateAllVoxels() { all++; }
    public void onUpdateVoxel(Location loc) { }
    public void onUpdateVoxel(Cube cube) { }
}

static class TimeTests
{
    [Test]
    static void StartTime()
    {
        Time t = Fixtures.NewTime(Time.START_TIME);
        Assert.Eq("1/4/1 8:00 dow6 Spring DayTime", t.year + "/" + t.month + "/" + t.day + " " + t.hour + ":" + t.minutes.ToString("00") + " dow" + t.dayOfWeek + " " + t.season + " " + t.dayOrNight, "start");
        Assert.Eq("Year 1 Month 4 Day 1 (6)  8:00", t.displayString, "status-bar string");
        Assert.Eq(0L, t.totalMinutes, "totalMinutes");
        Assert.Eq(Time.START_TIME, new Clock().totalMinutes + Time.START_TIME, "Clock starts at START_TIME");
    }

    [Test]
    static void CalendarAndSeasonTable()
    {
        List<string> lines = new List<string>();
        string prev = null;
        for (long day = 0; day <= 366; day++)
        {
            Time t = Fixtures.NewTime(day * Time.DAY + 12 * Time.HOUR);
            string season = t.season.ToString();
            if (season != prev || t.day == 1 || day >= 364)
                lines.Add(string.Format("day {0}: Y{1} M{2} D{3} dow{4} {5}{6}", day, t.year, t.month, t.day, t.dayOfWeek, season, t.isWeekend ? " weekend" : ""));
            prev = season;
        }
        Golden.Check("time-calendar-season", lines);
        Assert.Eq(Season.Winter, Fixtures.NewTime(58 * Time.DAY).season, "Feb 28 winter");
        Assert.Eq(Season.Spring, Fixtures.NewTime(59 * Time.DAY).season, "Mar 1 spring");
        Assert.Eq(Season.Summer, Fixtures.NewTime(151 * Time.DAY).season, "Jun 1 summer");
        Assert.Eq(Season.Autumn, Fixtures.NewTime(243 * Time.DAY).season, "Sep 1 autumn");
        Assert.Eq(Season.Winter, Fixtures.NewTime(334 * Time.DAY).season, "Dec 1 winter");
    }

    [Test]
    static void DayNightBoundaries()
    {
        StringBuilder sb = new StringBuilder();
        for (int m = 0; m < 24 * 60; m++)
            sb.Append(Fixtures.NewTime(100 * Time.DAY + m).dayOrNight == DayNight.Night ? 'N' : 'D');
        string s = sb.ToString();
        Assert.Eq(new string('N', 360) + new string('D', 720) + new string('N', 360), s, "day is [06:00,18:00)");
    }

    [Test]
    static void UseNightViewModes()
    {
        World w = Fixtures.NewWorld(2, 4, 2, 0);
        long[] times = { 100 * Time.DAY + 6 * Time.HOUR - 1, 100 * Time.DAY + 6 * Time.HOUR, 100 * Time.DAY + 18 * Time.HOUR - 1, 100 * Time.DAY + 18 * Time.HOUR };
        string[] expected = { "TFFT", "FFFF", "TTTT" };
        NightSpriteMode[] modes = { NightSpriteMode.AlignClock, NightSpriteMode.AlwaysDay, NightSpriteMode.AlwaysNight };
        Assert.Eq(NightSpriteMode.AlignClock, w.viewOptions.nightSpriteMode, "default mode");
        for (int i = 0; i < modes.Length; i++)
        {
            Fixtures.SetNightMode(w, modes[i]);
            StringBuilder sb = new StringBuilder();
            foreach (long t in times) { Fixtures.SetClock(w, t); sb.Append(w.viewOptions.useNightView ? 'T' : 'F'); }
            Assert.Eq(expected[i], sb.ToString(), modes[i].ToString());
        }
    }

    [Test]
    static void TickInvalidatesOnlyAtSunriseAndSunset()
    {
        World w = Fixtures.NewWorld(2, 4, 2, 0);
        // Debug-build Clock.tick asserts on queue.minPriority, which throws on an empty queue.
        w.clock.registerOneShot(delegate { }, TimeLength.fromHours(24 * 400));
        CountingListener l = new CountingListener();
        w.voxelOutlookListeners.Add(l);
        Picture pic = ResourceTests.NewPicture(new SurfaceLoader[4, 2] { { new FakeLoader("a"), null }, { null, null }, { null, null }, { null, null } });
        List<string> fired = new List<string>();
        Fixtures.SetClock(w, 5 * Time.DAY);
        for (int i = 0; i < 24 * 60; i++)
        {
            Fixtures.SetField(pic, "dirty", false);
            int before = l.all;
            IlTransplant.Invoke(Clones.Tick(), w.clock);
            bool dirty = (bool)Fixtures.GetField(pic, "dirty");
            if (dirty || l.all != before)
                fired.Add(w.clock.hour.ToString("00") + ":" + w.clock.minutes.ToString("00") + " dirty=" + dirty + " repaint=" + (l.all - before));
        }
        Assert.Eq("06:00 dirty=True repaint=1|18:00 dirty=True repaint=1", string.Join("|", fired.ToArray()), "tick side effects");
    }
}

sealed class SelectedException : Exception
{
    public readonly string Loader;
    public SelectedException(string l) : base(l) { Loader = l; }
}

sealed class FakeLoader : SurfaceLoader
{
    public readonly string Name;
    public FakeLoader(string n) { Name = n; }
    public Color load(ref org.kohsuke.directdraw.Surface s) { throw new SelectedException(Name); }
}

static class ResourceTests
{
    static int seq;

    public static Picture NewPicture(SurfaceLoader[,] l) { return new Picture("test-" + (seq++), l); }

    static string Describe(SurfaceLoader l)
    {
        if (l == null) return "null";
        if (l is FakeLoader) return ((FakeLoader)l).Name;
        if (l is NightSurfaceLoader) return "night(" + Describe((SurfaceLoader)Fixtures.GetField(l, "coreLoader")) + ")";
        if (l is BitmapSurfaceLoader) return Path.GetFileName((string)Fixtures.GetField(l, "fileName"));
        return l.GetType().Name;
    }

    static string Table(Picture p)
    {
        SurfaceLoader[,] t = (SurfaceLoader[,])Fixtures.GetField(p, "loaders");
        string[] parts = new string[4];
        for (int s = 0; s < 4; s++) parts[s] = ((Season)s) + "=" + Describe(t[s, 0]) + "/" + Describe(t[s, 1]);
        return string.Join(" ", parts);
    }

    static SurfaceLoader[,] Spec(params object[] slots)
    {
        SurfaceLoader[,] r = new SurfaceLoader[4, 2];
        for (int i = 0; i < slots.Length; i += 3) r[(int)slots[i], (int)slots[i + 1]] = new FakeLoader((string)slots[i + 2]);
        return r;
    }

    [Test]
    static void PictureLoaderTableFill()
    {
        List<string> lines = new List<string>();
        lines.Add(Table(NewPicture(Spec(0, 0, "A"))));
        lines.Add(Table(NewPicture(Spec(0, 0, "A", 3, 0, "W"))));
        lines.Add(Table(NewPicture(Spec(0, 0, "A", 0, 1, "N", 1, 1, "SN"))));
        lines.Add(Table(NewPicture(Spec(0, 0, "A", 2, 0, "F", 2, 1, "FN"))));
        lines.Add(Table(NewPicture(Spec(1, 0, "S"))));
        lines.Add(Table(NewPicture(Spec(0, 0, "A", 3, 1, "WN"))));
        Golden.Check("picture-loader-table", lines);

        Picture one = NewPicture(Spec(0, 0, "A"));
        SurfaceLoader[,] t = (SurfaceLoader[,])Fixtures.GetField(one, "loaders");
        Assert.True(t[1, 1] == t[0, 1] && t[3, 1] == t[0, 1], "unspecified seasons share spring's night loader instance");
    }

    [Test]
    static void PictureSurfaceSelectsSeasonAndNight()
    {
        World w = Fixtures.NewWorld(2, 4, 2, 0);
        SurfaceLoader[,] all = new SurfaceLoader[4, 2];
        for (int s = 0; s < 4; s++) { all[s, 0] = new FakeLoader(s + "d"); all[s, 1] = new FakeLoader(s + "n"); }
        Picture p = NewPicture(all);
        long[] seasonDays = { 100, 200, 260, 10 };   // Apr, Jul, Sep, Jan
        List<string> got = new List<string>();
        foreach (NightSpriteMode mode in new NightSpriteMode[] { NightSpriteMode.AlignClock, NightSpriteMode.AlwaysDay, NightSpriteMode.AlwaysNight })
            foreach (long day in seasonDays)
                foreach (int hour in new int[] { 12, 22 })
                {
                    Fixtures.SetNightMode(w, mode);
                    Fixtures.SetClock(w, day * Time.DAY + hour * Time.HOUR);
                    p.setDirty();
                    try { object o = p.surface; got.Add("no load"); }
                    catch (SelectedException e) { got.Add(e.Loader); }
                }
        Assert.Eq("0d 0n 1d 1n 2d 2n 3d 3n | 0d 0d 1d 1d 2d 2d 3d 3d | 0n 0n 1n 1n 2n 2n 3n 3n",
            string.Join(" ", got.GetRange(0, 8).ToArray()) + " | " + string.Join(" ", got.GetRange(8, 8).ToArray()) + " | " + string.Join(" ", got.GetRange(16, 8).ToArray()),
            "loaders[season, useNightView]");
    }

    static Picture FromXml(string xml)
    {
        string dir = Path.Combine(Path.GetTempPath(), "ft-code-derived");
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "picture-" + (seq++) + ".xml");
        File.WriteAllText(path, xml);
        XmlDocument doc = new XmlDocument();
        doc.Load(path);
        XmlElement e = doc.DocumentElement;
        e.SetAttribute("id", "xml-" + (seq++));
        return new Picture(e);
    }

    [Test]
    static void PictureXmlOverrides()
    {
        List<string> lines = new List<string>();
        lines.Add(Table(FromXml("<picture src='b.bmp'/>")));
        lines.Add(Table(FromXml("<picture src='b.bmp'><override when='night' src='b_n.bmp'/></picture>")));
        lines.Add(Table(FromXml(
            "<picture src='b.bmp'><override when='night' src='b_n.bmp'/>" +
            "<override when='winter' src='w.bmp'><override when='night' src='w_n.bmp'/></override>" +
            "<override when='summer' src='s.bmp'/><override when='fall' src='f.bmp'/></picture>")));
        // night override that is not the first <override> child is not found
        lines.Add(Table(FromXml("<picture src='b.bmp'><override when='winter' src='w.bmp'/><override when='night' src='b_n.bmp'/></picture>")));
        // season override without src keeps the base day image but may carry its own night image
        lines.Add(Table(FromXml("<picture src='b.bmp'><override when='autumn'><override when='night' src='a_n.bmp'/></override></picture>")));
        Golden.Check("picture-xml-overrides", lines);
        Assert.Throws<FormatException>(delegate { FromXml("<picture src='b.bmp'><override when='rainy' src='r.bmp'/></picture>"); }, "unknown when");
    }

    [Test]
    static void NightColorMap()
    {
        Assert.Eq(Color.FromArgb(255, 8, 8).ToArgb(), ColorMap.getNightColor(Color.FromArgb(8, 0, 0)).ToArgb(), "light 1");
        Assert.Eq(Color.FromArgb(252, 243, 148).ToArgb(), ColorMap.getNightColor(Color.FromArgb(0, 8, 0)).ToArgb(), "light 2");
        Assert.Eq(Color.FromArgb(255, 227, 99).ToArgb(), ColorMap.getNightColor(Color.FromArgb(0, 0, 8)).ToArgb(), "light 3");
        Assert.Eq(Color.FromArgb(63, 28, 1).ToArgb(), ColorMap.getNightColor(Color.FromArgb(255, 114, 7)).ToArgb(), "others: each channel /4, alpha 255");
        Assert.Eq(Color.FromArgb(255, 2, 2, 2).ToArgb(), ColorMap.getNightColor(Color.FromArgb(10, 8, 8, 8)).ToArgb(), "alpha is not compared or kept");
        Assert.Eq(Color.FromArgb(2, 0, 0).ToArgb(), ColorMap.getNightColor(Color.FromArgb(128, 8, 0, 0)).ToArgb(), "light match needs alpha 255");
    }

    [Test]
    static void GroundChipBySeason()
    {
        World w = Fixtures.NewWorld(2, 4, 2, 0);
        List<string> got = new List<string>();
        foreach (long day in new long[] { 58, 59, 333, 334, 364 })
        {
            Fixtures.SetClock(w, day * Time.DAY);
            got.Add(w.clock.season + "=" + IlTransplant.Invoke(Clones.GetGroundChip(), w));
        }
        Assert.Eq("Winter=winterGround Spring=ground Autumn=ground Winter=winterGround Winter=winterGround", string.Join(" ", got.ToArray()), "getGroundChip");
    }

    static string Hex(Color c) { return (c.ToArgb() & 0xffffff).ToString("X6"); }

    [Test]
    static void MountainPaletteFromShippedXml()
    {
        XmlDocument doc = new XmlDocument();
        doc.Load(Path.Combine(Program.PackageRoot, @"res\mountainPalette.xml"));
        List<string> lines = new List<string>();
        foreach (string s in new string[] { "spring", "summer", "autumn", "winter", "water" })
        {
            Color[] cs = (Color[])IlTransplant.Invoke(Clones.LoadColors(), (XmlElement)doc.SelectSingleNode("/*/" + s));
            lines.Add(s + " " + cs.Length + ": " + string.Join(" ", Array.ConvertAll(cs, Hex)));
        }
        Golden.Check("mountain-palette", lines);
    }

    [Test]
    static void FromHsvSamples()
    {
        List<string> lines = new List<string>();
        foreach (int[] c in new int[][] { new[] { 0, 240, 239 }, new[] { 39, 125, 78 }, new[] { 40, 240, 239 }, new[] { 60, 162, 90 }, new[] { 69, 185, 70 }, new[] { 120, 0, 120 }, new[] { 200, 100, 200 }, new[] { 239, 240, 239 }, new[] { 240, 100, 100 } })
            lines.Add(c[0] + "," + c[1] + "," + c[2] + " -> " + Hex((Color)IlTransplant.Invoke(Clones.FromHsv(), c[0], c[1], c[2])));
        Golden.Check("mountain-fromhsv", lines);
        // V=240 gives 256*1.0 = 256 for the top channel, which Color.FromArgb rejects.
        Assert.Throws<ArgumentException>(delegate { IlTransplant.Invoke(Clones.FromHsv(), 0, 0, 240); }, "V=240 overflows");
    }

    [Test]
    static void MountainColorsIndexedBySeason()
    {
        World w = Fixtures.NewWorld(2, 4, 2, 0);
        Seams.MountainColors = new Color[4][];
        for (int s = 0; s < 4; s++) Seams.MountainColors[s] = new Color[] { Color.FromArgb(s, 0, 0) };
        foreach (long day in new long[] { 100, 200, 260, 10 })
        {
            Fixtures.SetClock(w, day * Time.DAY);
            Color[] c = (Color[])IlTransplant.Invoke(Clones.CurrentMountainColors(), new object[] { null });
            Assert.Eq((int)w.clock.season, (int)c[0].R, "mountainColors[(int)season] on day " + day);
        }
    }

    [Test]
    static void MountainSelectColorTable()
    {
        XmlDocument doc = new XmlDocument();
        doc.Load(Path.Combine(Program.PackageRoot, @"res\mountainPalette.xml"));
        Seams.MountainColors = new Color[4][];
        string[] names = { "spring", "summer", "autumn", "winter" };
        for (int s = 0; s < 4; s++) Seams.MountainColors[s] = (Color[])IlTransplant.Invoke(Clones.LoadColors(), (XmlElement)doc.SelectSingleNode("/*/" + names[s]));
        Seams.WaterColors = (Color[])IlTransplant.Invoke(Clones.LoadColors(), (XmlElement)doc.SelectSingleNode("/*/water"));

        World w = Fixtures.NewWorld(4, 8, 4, 1);
        MountainStandIn mv = new MountainStandIn();
        List<string> lines = new List<string>();
        foreach (int z in new int[] { 1, 0 })   // dry, under water
            foreach (NightSpriteMode mode in new NightSpriteMode[] { NightSpriteMode.AlwaysDay, NightSpriteMode.AlwaysNight })
                foreach (long day in new long[] { 100, 200, 260, 10 })
                {
                    mv.Location = new Location(3, 3, z);
                    Fixtures.SetNightMode(w, mode);
                    Fixtures.SetClock(w, day * Time.DAY);
                    StringBuilder sb = new StringBuilder();
                    // all 625 corner-height combinations, NE major ... NW minor
                    for (int code = 0; code < 625; code++)
                    {
                        mv.Heights[0] = code / 125; mv.Heights[1] = code / 25 % 5; mv.Heights[2] = code / 5 % 5; mv.Heights[3] = code % 5;
                        Color c = (Color)IlTransplant.Invoke(Clones.SelectColor(), mv);
                        if (code > 0) sb.Append(' ');
                        sb.Append(Hex(c));
                    }
                    lines.Add("z=" + z + " " + mode + " " + w.clock.season + ": " + sb);
                }
        Golden.Check("mountain-selectcolor", lines);
    }
}
