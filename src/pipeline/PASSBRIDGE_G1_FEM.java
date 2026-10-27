import com.comsol.model.*;
import com.comsol.model.util.*;
import java.util.*;

/** PASSBRIDGE G1 2m x 2m physically explicit structural FEM model, COMSOL 6.4.
 *  Uses 3-D solid mechanics. Steel/zinc EM coating is NOT used as structural solid.
 *  Thin sheet + hollow RHS profiles may need significant RAM for tetrahedral meshing.
 *  All pressure/anchor values are declared engineering scenarios, not building-code certification.
 */
public class PASSBRIDGE_G1_FEM {
    static final Locale LOCALE = Locale.US;
    static final double SHEET = 0.0012;
    static final double GAP = 0.002;
    static final double RHO_AIR=1.225, CF=1.8;
    static final String OUT_DIR = "__PASSBRIDGE_OUT_DIR__";
    static Model m;
    static GeomSequence g;
    static int id = 0;

    static String n(double v) { return String.format(LOCALE,"%.9f",v); }
    static String[] a(double... v) { String[] q=new String[v.length]; for (int i=0;i<v.length;i++) q[i]=n(v[i]); return q; }
    static void say(String s) { System.out.println("PASSBRIDGE | " + s); System.out.flush(); }
    static void addBlock(String tag, double x0,double y0,double z0,double dx,double dy,double dz) {
        g.create(tag,"Block");
        g.feature(tag).set("base","corner");
        g.feature(tag).set("pos",a(x0,y0,z0));
        g.feature(tag).set("size",a(dx,dy,dz));
    }
    static void rhsX(String name,double xc,double yc,double zTop,double length,double width,double height,double wall) {
        // X oriented rectangular hollow structural steel tube; open-ended difference.
        String bo=name+"o", bi=name+"i";
        addBlock(bo,xc-length/2,yc-width/2,zTop-height,length,width,height);
        addBlock(bi,xc-length/2-0.001,yc-width/2+wall,zTop-height+wall,length+0.002,width-2*wall,height-2*wall);
        g.create(name,"Difference");
        g.feature(name).selection("input").set(new String[]{bo});
        g.feature(name).selection("input2").set(new String[]{bi});
        g.feature(name).set("selresult",true);
    }
    static void rhsY(String name,double xc,double yc,double zTop,double length,double width,double height,double wall) {
        String bo=name+"o", bi=name+"i";
        addBlock(bo,xc-width/2,yc-length/2,zTop-height,width,length,height);
        addBlock(bi,xc-width/2+wall,yc-length/2-0.001,zTop-height+wall,width-2*wall,length+0.002,height-2*wall);
        g.create(name,"Difference");
        g.feature(name).selection("input").set(new String[]{bo});
        g.feature(name).selection("input2").set(new String[]{bi});
        g.feature(name).set("selresult",true);
    }
    static void boxSelection(String tag,double x0,double x1,double y0,double y1,double z0,double z1) {
        m.component("comp1").selection().create(tag,"Box");
        m.component("comp1").selection(tag).set("entitydim",2);
        m.component("comp1").selection(tag).set("condition","inside");
        m.component("comp1").selection(tag).set("xmin",x0);
        m.component("comp1").selection(tag).set("xmax",x1);
        m.component("comp1").selection(tag).set("ymin",y0);
        m.component("comp1").selection(tag).set("ymax",y1);
        m.component("comp1").selection(tag).set("zmin",z0);
        m.component("comp1").selection(tag).set("zmax",z1);
    }
    /** Evaluate only *selected* structural domains on the current solution dataset.
     *  Earlier code failed because the MaxVolume node had no explicit selection,
     *  returning NaN even after COMSOL solved the full model.
     */
    static double measure(String tag, String expression) {
        String unit=expression.equals("solid.disp") ? "mm" : "MPa";
        double value=Double.NaN;
        try {
            m.result().numerical().create(tag,"MaxVolume");
            m.result().numerical(tag).selection().all();
            m.result().numerical(tag).set("expr",new String[]{expression});
            m.result().numerical(tag).set("unit",new String[]{unit});
            // The existing stationary study should create the first solution dataset.
            try { m.result().numerical(tag).set("data","dset1"); }
            catch(Throwable ex) { say("DATASET_NOTE "+ex.toString()); }
            double[][] a=m.result().numerical(tag).getReal();
            if(a!=null) for(double[] row:a) if(row!=null)
                for(double x:row) if(Double.isFinite(x)) value=Double.isFinite(value)?Math.max(value,x):x;
        } catch(Throwable ex) {
            say("MAX_VOLUME_WARNING "+expression+" "+ex.toString());
        } finally {
            try {m.result().numerical().remove(tag);}catch(Throwable ignored){}
        }
        if(Double.isFinite(value)) return value;
        // COMSOL 6.4 also documents an API-level Eval feature that reads raw
        // solution data, bypassing the derived-value selection/maximum node.
        String alt=tag+"Eval";
        try {
            m.result().numerical().create(alt,"Eval");
            m.result().numerical(alt).selection().all();
            m.result().numerical(alt).set("expr",new String[]{expression});
            try { m.result().numerical(alt).set("data","dset1"); }
            catch(Throwable ex) { say("EVAL_DATASET_NOTE "+ex.toString()); }
            double[][] values=m.result().numerical(alt).getData(0);
            // Eval returns default SI units: m for displacement and Pa for stress.
            // Convert displacements to mm (x1000), stress to MPa (x1e-6).
            double scale=expression.equals("solid.disp") ? 1.0e3 : 1.0e-6;
            if(values!=null) for(double[] row:values) if(row!=null)
                for(double x:row) if(Double.isFinite(x))
                    value=Double.isFinite(value)?Math.max(value,x*scale):(x*scale);
            say("EVAL_FALLBACK "+expression+" max="+value);
        } catch(Throwable ex) {
            say("EVAL_FALLBACK_WARNING "+expression+" "+ex.toString());
        } finally {
            try {m.result().numerical().remove(alt);}catch(Throwable ignored){}
        }
        return value;
    }
    static void captureFailure(Throwable e) {
        say("ERROR " + e.toString());
        e.printStackTrace(System.err);
        if (m != null) {
            try { m.save(OUT_DIR + "/PASSBRIDGE_G1_RECOVERY.mph"); }
            catch (Throwable saveError) { say("RECOVERY_SAVE_FAILED " + saveError.toString()); }
        }
    }
    public static void main(String[] args) { run(); }
    public static Model run() {
        // Do not call System.getenv, System.getProperty or Java filesystem APIs:
        // COMSOL 6.4 method security can block them before the solver starts.
        // BASLAT.ps1 injects the selected output directory into OUT_DIR at compile time.
        try {
            say("START PASSBRIDGE FULL 2m G1 Solid FEM model");
            m=ModelUtil.create("PASSBRIDGE_G1_FULL");
            m.modelPath(OUT_DIR);
            m.label("PASSBRIDGE_G1_FULL_STRUCTURAL.mph");
            m.param().set("pwind","248.0625[Pa]","Uniform equivalent pressure. Not site-code design load.");
            m.param().set("E_nom","210[GPa]","Nominal structural steel elasticity, DX51D certificate pending");
            m.param().set("rho_nom","7850[kg/m^3]");
            m.param().set("nu_nom","0.3");
            m.component().create("comp1",true);
            g=m.component("comp1").geom().create("geom1",3);
            g.lengthUnit("m");
            // Two real 999 x 2000 x 1.2 mm separate finite steel sheets.
            addBlock("sheetL",-1.0,-1.0,-SHEET,0.999,2.0,SHEET);
            addBlock("sheetR",0.001,-1.0,-SHEET,0.999,2.0,SHEET);
            // 50x50x3 mm structural steel perimeter RHS, 4 sides, behind steel sheet.
            rhsX("topRHS",0,+0.975,-SHEET,2.0,0.05,0.05,0.003);
            rhsX("botRHS",0,-0.975,-SHEET,2.0,0.05,0.05,0.003);
            rhsY("leftRHS",-0.975,0,-SHEET,2.0,0.05,0.05,0.003);
            rhsY("rightRHS",+0.975,0,-SHEET,2.0,0.05,0.05,0.003);
            // 40x20x2 mm rectangular hollow inner stiffeners; 40 mm section height normal to sheet.
            rhsX("railHX1",0,-0.5,-SHEET,1.9,0.02,0.04,0.002);
            rhsX("railHX2",0,0.0,-SHEET,1.9,0.02,0.04,0.002);
            rhsX("railHX3",0,+0.5,-SHEET,1.9,0.02,0.04,0.002);
            rhsY("railVY1",-0.5,0,-SHEET,1.9,0.02,0.04,0.002);
            rhsY("railVY2",0.0,0,-SHEET,1.9,0.02,0.04,0.002);
            rhsY("railVY3",+0.5,0,-SHEET,1.9,0.02,0.04,0.002);
            // Four welded conceptual 100x100x8mm mounting plates on inner rail backs.
            // Actual bolts/pole/anchor stiffness are NOT simulated as real site connections.
            int j=0;
            for(double x:new double[]{-0.5,0.5}) for(double y:new double[]{-0.5,0.5}) {
                addBlock("pad"+(++j),x-0.05,y-0.05,-SHEET-0.04-0.008,0.1,0.1,0.008);
            }
            say("GEOMETRY: two sheet halves + 4 perimeter RHS + 6 inner RHS + 4 mounting pads");
            // COMSOL finalization automatically forms union; physical overlaps imply bonded/welded joints.
            g.run();
            say("GEOMETRY_BUILT");
            m.save(OUT_DIR + "/PASSBRIDGE_G1_GEOMETRY.mph");
            // Explicit boundary selections AFTER finalization, insensitive to entity renumbering.
            boxSelection("selFront",-1.0001,1.0001,-1.0001,1.0001,-0.00002,+0.00002);
            for(int k=0;k<4;k++) {
                double x=(k<2 ? -0.5 : +0.5);
                double y=(k%2==0 ? -0.5 : +0.5);
                boxSelection("selFix"+k,x-0.051,x+0.051,y-0.051,y+0.051,-0.04922,-0.04918);
            }
            // Steel properties are nominal and equal for both sheet/frame for this first elastic structural model.
            m.component("comp1").material().create("mat1","Common");
            m.component("comp1").material("mat1").label("DX51D sheet and S235JR frame - nominal common elastic law");
            m.component("comp1").material("mat1").propertyGroup("def").set("youngsmodulus","E_nom");
            m.component("comp1").material("mat1").propertyGroup("def").set("poissonsratio","nu_nom");
            m.component("comp1").material("mat1").propertyGroup("def").set("density","rho_nom");
            m.component("comp1").physics().create("solid","SolidMechanics","geom1");
            for(int k=0;k<4;k++) {
                String ft="fix"+k;
                m.component("comp1").physics("solid").create(ft,"Fixed",2);
                m.component("comp1").physics("solid").feature(ft).selection().named("selFix"+k);
            }
            m.component("comp1").physics("solid").create("wind","BoundaryLoad",2);
            m.component("comp1").physics("solid").feature("wind").selection().named("selFront");
            // pressure sign convention inward-to-solid on +Z front surface -> negative Z.
            // COMSOL 6.4 Solid Mechanics Java API calls this boundary pressure
            // mode FollowerPressure (NOT Pressure). This is confirmed by
            // forceType enum in the running COMSOL error and API examples.
            m.component("comp1").physics("solid").feature("wind").set("LoadType","FollowerPressure");
            m.component("comp1").physics("solid").feature("wind").set("FollowerPressure","pwind");
            say("PRESSURE_BOUNDARY_CONFIGURED");
            m.component("comp1").mesh().create("mesh1");
            m.study().create("std1");
            m.study("std1").create("stat","Stationary");
            m.study("std1").feature("stat").setSolveFor("/physics/solid",true);
            say("PHYSICS_BUILT");
            m.save(OUT_DIR + "/PASSBRIDGE_G1_PHYSICS.mph");
            // Emit structured case records on stdout; the PowerShell supervisor
            // converts them to CSV and keeps the full COMSOL batch log.
            // Separate runs are saved only if COMSOL actually solved successfully.
            for (int meshSize:new int[]{7,6,5}) {
                say("MESH_ATTEMPT autoMeshSize="+meshSize);
                try {
                    m.component("comp1").mesh("mesh1").autoMeshSize(meshSize);
                    m.component("comp1").mesh("mesh1").run();
                    say("MESH_BUILT size="+meshSize);
                } catch(Throwable e) {
                    say("MESH_FAIL size="+meshSize+" reason="+e);
                    e.printStackTrace(System.err);
                    break;
                }
                for(double V:new double[]{15,25,35}) {
                    double pressure=0.5*RHO_AIR*V*V*CF;
                    m.param().set("pwind",n(pressure)+"[Pa]");
                    say("SOLVER_START mesh="+meshSize+" V="+V+" p="+pressure);
                    try {
                        m.study("std1").run();
                        say("SOLVER_FINISH mesh="+meshSize+" V="+V);
                        String stem="G1_MESH"+meshSize+"_W"+(int)V;
                        // CRITICAL: preserve the genuine solved .mph before ANY
                        // derived-value call. A postprocessing error cannot discard
                        // an already-completed FEM solution ever again.
                        m.save(OUT_DIR + "/" + stem + ".mph");
                        say("CASE_SOLVED|"+meshSize+"|"+(int)V+"|"+n(pressure)+"|"+stem+".mph");
                        double d=measure("evd","solid.disp");
                        double vm=measure("evs","solid.mises");
                        if(Double.isFinite(d)&&Double.isFinite(vm)&&d>=0&&vm>=0) {
                            say("CASE_OK|"+meshSize+"|"+(int)V+"|"+n(pressure)+"|"+n(d)+"|"+n(vm)+"|"+stem+".mph");
                        } else {
                            say("MEASUREMENT_PENDING|"+meshSize+"|"+(int)V+"|d="+d+"|vm="+vm);
                        }
                        try {
                            m.result().export().create("uExport","Data");
                            m.result().export("uExport").set("expr",new String[]{"u","v","w","solid.disp"});
                            m.result().export("uExport").set("filename",OUT_DIR + "/" + stem + "_DISPLACEMENT.txt");
                            m.result().export("uExport").set("struct","spreadsheet");
                            m.result().export("uExport").run();
                            m.result().export().remove("uExport");
                            say("DISPLACEMENT_EXPORTED mesh="+meshSize+" wind="+V);
                        } catch(Throwable exportError) {
                            say("DISPLACEMENT_EXPORT_WARNING mesh="+meshSize+" wind="+V+" error="+exportError);
                            try { m.result().export().remove("uExport"); } catch(Throwable ignored) {}
                        }
                    } catch(Throwable e) {
                        say("CASE_FAIL|"+meshSize+"|"+(int)V+"|"+n(pressure)+"|"+e.toString().replace('|','/'));
                        e.printStackTrace(System.err);
                        break;
                    }
                }
            }
            // Final project may contain latest solution, and all intermediate proven MPH files.
            m.save(OUT_DIR + "/PASSBRIDGE_G1_FINAL_STRUCTURAL.mph");
            say("FINISHED. Supervisor will extract CASE_OK entries to FEM_RESULTS.csv.");
            return m;
        } catch(Throwable e) {
            captureFailure(e);
            throw new RuntimeException(e);
        }
    }
}
