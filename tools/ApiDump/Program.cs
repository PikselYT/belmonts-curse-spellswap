using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

// Dumps types/members of the BepInEx-generated interop assemblies matching a regex.
// usage: ApiDump <gameDir> <assemblyName> <typeRegex> [memberRegex]
var game = args[0];
var asmName = args[1];
var typeRx = new Regex(args[2], RegexOptions.IgnoreCase);
var memberRx = args.Length > 3 ? new Regex(args[3], RegexOptions.IgnoreCase) : null;

var dirs = new[] { Path.Combine(game, "BepInEx", "interop"), Path.Combine(game, "BepInEx", "core"), RuntimeEnvironment.GetRuntimeDirectory() };
var files = dirs.Where(Directory.Exists).SelectMany(d => Directory.GetFiles(d, "*.dll")).ToList();
var resolver = new PathAssemblyResolver(files);
using var mlc = new MetadataLoadContext(resolver, "System.Private.CoreLib");
var asm = mlc.LoadFromAssemblyPath(Path.Combine(dirs[0], asmName + ".dll"));

string N(Type t)
{
    try { return t.IsGenericType ? t.Name.Split('`')[0] + "<" + string.Join(",", t.GetGenericArguments().Select(N)) + ">" : t.Name; }
    catch { return "?"; }
}

Type[] types;
try { types = asm.GetTypes(); } catch (ReflectionTypeLoadException e) { types = e.Types.Where(t => t != null).ToArray(); }

foreach (var t in types.Where(t => typeRx.IsMatch(t.FullName ?? t.Name)).OrderBy(t => t.FullName))
{
    string bt; try { bt = t.BaseType == null ? "" : " : " + N(t.BaseType); } catch { bt = ""; }
    var lines = new List<string>();
    const BindingFlags F = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;
    try
    {
        foreach (var m in t.GetMethods(F).Where(m => !m.IsSpecialName || m.Name.StartsWith("get_") || m.Name.StartsWith("set_")))
        {
            if (memberRx != null && !memberRx.IsMatch(m.Name)) continue;
            if (m.Name.StartsWith("NativeMethodInfoPtr")) continue;
            string ps; try { ps = string.Join(", ", m.GetParameters().Select(p => N(p.ParameterType) + " " + p.Name)); } catch { ps = "?"; }
            string rt; try { rt = N(m.ReturnType); } catch { rt = "?"; }
            lines.Add($"   {(m.IsStatic ? "static " : "")}{rt} {m.Name}({ps})");
        }
        foreach (var f in t.GetProperties(F))
        {
            if (memberRx != null && !memberRx.IsMatch(f.Name)) continue;
            lines.Add($"   prop {N(f.PropertyType)} {f.Name}");
        }
    }
    catch (Exception e) { lines.Add("   (members unavailable: " + e.GetType().Name + ")"); }
    if (memberRx != null && lines.Count == 0) continue;
    Console.WriteLine();
    Console.WriteLine($"{t.FullName}{bt}");
    foreach (var l in lines) Console.WriteLine(l);
}
