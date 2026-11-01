// Test-only seam: copies the IL of a shipped FreeTrain method into a DynamicMethod,
// optionally redirecting selected member references to test doubles.
//
// Why: several pure-logic methods live on types whose static constructors create
// DirectDraw surfaces (ResourceUtil, MountainVoxel) or whose instance state is a
// DirectDraw surface (QuarterViewDrawer). Running the copied body executes the exact
// shipped IL without touching the declaring type's static constructor, and the
// substitutions replace only the DirectDraw-touching references.
//
// Every substitution keeps instruction sizes unchanged (a 5-byte call/callvirt/ldsfld
// becomes a 5-byte call), so branch offsets and exception clauses are copied verbatim.
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;

static class IlTransplant
{
    static readonly OpCode[] oneByte = new OpCode[0x100];
    static readonly OpCode[] twoByte = new OpCode[0x100];

    static IlTransplant()
    {
        foreach (FieldInfo f in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            OpCode op = (OpCode)f.GetValue(null);
            ushort v = (ushort)op.Value;
            if (op.Size == 1) oneByte[v] = op;
            else twoByte[v & 0xff] = op;
        }
    }

    /// <summary>
    /// Clones <paramref name="source"/>. Keys of <paramref name="subs"/> are fields
    /// (only <c>ldsfld</c> is redirected) or methods (<c>call</c>/<c>callvirt</c>);
    /// values are static methods (or DynamicMethods) with the same stack shape:
    /// an instance call's receiver becomes the first parameter.
    /// The clone of an instance method takes the receiver as its first parameter.
    /// </summary>
    public static DynamicMethod Clone(MethodBase source, IDictionary<MemberInfo, MethodInfo> subs)
    {
        return Clone(source, subs, null);
    }

    /// <summary>
    /// As above, but declares the receiver parameter as <paramref name="receiverType"/>
    /// (for example <c>object</c>). This lets an instance body run on a stand-in when the
    /// declaring type cannot be instantiated; the body must then reach the receiver only
    /// through substituted members. Full-trust DynamicMethod IL is not verified.
    /// </summary>
    public static DynamicMethod Clone(MethodBase source, IDictionary<MemberInfo, MethodInfo> subs, Type receiverType)
    {
        if (subs == null) subs = new Dictionary<MemberInfo, MethodInfo>();
        MethodBody body = source.GetMethodBody();
        Module module = source.Module;
        Type[] typeArgs = source.DeclaringType.IsGenericType ? source.DeclaringType.GetGenericArguments() : null;

        List<Type> ps = new List<Type>();
        if (!source.IsStatic) ps.Add(receiverType ?? source.DeclaringType);
        foreach (ParameterInfo p in source.GetParameters()) ps.Add(p.ParameterType);
        Type ret = source is MethodInfo ? ((MethodInfo)source).ReturnType : typeof(void);

        DynamicMethod dm = new DynamicMethod("transplant_" + source.DeclaringType.Name + "_" + source.Name,
            ret, ps.ToArray(), typeof(IlTransplant), true);
        DynamicILInfo info = dm.GetDynamicILInfo();

        byte[] il = (byte[])body.GetILAsByteArray().Clone();
        Dictionary<MemberInfo, MethodInfo> asDict = subs as Dictionary<MemberInfo, MethodInfo>;
        HashSet<MemberInfo> matched = asDict != null ? new HashSet<MemberInfo>(asDict.Comparer) : new HashSet<MemberInfo>();
        int pos = 0;
        while (pos < il.Length)
        {
            int opStart = pos;
            OpCode op;
            if (il[pos] == 0xFE) { op = twoByte[il[pos + 1]]; pos += 2; }
            else { op = oneByte[il[pos]]; pos += 1; }

            switch (op.OperandType)
            {
                case OperandType.InlineNone: break;
                case OperandType.ShortInlineBrTarget:
                case OperandType.ShortInlineI:
                case OperandType.ShortInlineVar: pos += 1; break;
                case OperandType.InlineVar: pos += 2; break;
                case OperandType.InlineBrTarget:
                case OperandType.InlineI:
                case OperandType.ShortInlineR: pos += 4; break;
                case OperandType.InlineI8:
                case OperandType.InlineR: pos += 8; break;
                case OperandType.InlineSwitch:
                    pos += 4 + 4 * BitConverter.ToInt32(il, pos);
                    break;
                case OperandType.InlineString:
                    Patch(il, pos, info.GetTokenFor(module.ResolveString(BitConverter.ToInt32(il, pos))));
                    pos += 4;
                    break;
                case OperandType.InlineSig:
                    Patch(il, pos, info.GetTokenFor(module.ResolveSignature(BitConverter.ToInt32(il, pos))));
                    pos += 4;
                    break;
                case OperandType.InlineType:
                case OperandType.InlineField:
                case OperandType.InlineMethod:
                case OperandType.InlineTok:
                {
                    MemberInfo m = module.ResolveMember(BitConverter.ToInt32(il, pos), typeArgs, null);
                    MethodInfo sub;
                    if (subs.TryGetValue(m, out sub))
                    {
                        if (op != OpCodes.Ldsfld && op != OpCodes.Call && op != OpCodes.Callvirt)
                            throw new InvalidOperationException(Describe(source) + ": " + op + " of substituted " + m.Name + " cannot be redirected");
                        matched.Add(m);
                        il[opStart] = (byte)OpCodes.Call.Value;
                        Patch(il, pos, sub is DynamicMethod ? info.GetTokenFor((DynamicMethod)sub) : info.GetTokenFor(sub.MethodHandle));
                    }
                    else
                    {
                        Patch(il, pos, TokenFor(info, m));
                    }
                    pos += 4;
                    break;
                }
                default:
                    throw new NotSupportedException(op.OperandType.ToString());
            }
        }

        // A substitution that matches nothing means the shipped body is not the one the
        // test was written against, or the key names the wrong member: fail, never ignore.
        foreach (MemberInfo key in subs.Keys)
            if (!matched.Contains(key))
                throw new InvalidOperationException(Describe(source) + ": substitution for " + key.DeclaringType.Name + "." + key.Name + " matched no instruction");

        SignatureHelper locals = SignatureHelper.GetLocalVarSigHelper();
        foreach (LocalVariableInfo lv in body.LocalVariables) locals.AddArgument(lv.LocalType, lv.IsPinned);
        info.SetLocalSignature(locals.GetSignature());
        info.SetCode(il, body.MaxStackSize);
        dm.InitLocals = body.InitLocals;

        IList<ExceptionHandlingClause> clauses = body.ExceptionHandlingClauses;
        if (clauses.Count > 0)
        {
            // Fat exception-handling section (ECMA-335 II.25.4.6).
            byte[] eh = new byte[4 + 24 * clauses.Count];
            int size = eh.Length;
            eh[0] = 0x41;
            eh[1] = (byte)size; eh[2] = (byte)(size >> 8); eh[3] = (byte)(size >> 16);
            for (int i = 0; i < clauses.Count; i++)
            {
                ExceptionHandlingClause c = clauses[i];
                int o = 4 + 24 * i;
                Patch(eh, o, (int)c.Flags);
                Patch(eh, o + 4, c.TryOffset);
                Patch(eh, o + 8, c.TryLength);
                Patch(eh, o + 12, c.HandlerOffset);
                Patch(eh, o + 16, c.HandlerLength);
                int extra = 0;
                if (c.Flags == ExceptionHandlingClauseOptions.Clause) extra = info.GetTokenFor(c.CatchType.TypeHandle);
                else if (c.Flags == ExceptionHandlingClauseOptions.Filter) extra = c.FilterOffset;
                Patch(eh, o + 20, extra);
            }
            info.SetExceptions(eh);
        }
        return dm;
    }

    static string Describe(MethodBase m) { return m.DeclaringType.Name + "." + m.Name; }

    static int TokenFor(DynamicILInfo info, MemberInfo m)
    {
        if (m is Type) return info.GetTokenFor(((Type)m).TypeHandle);
        if (m is FieldInfo)
        {
            FieldInfo f = (FieldInfo)m;
            return info.GetTokenFor(f.FieldHandle, f.DeclaringType.TypeHandle);
        }
        MethodBase mb = (MethodBase)m;
        return info.GetTokenFor(mb.MethodHandle, mb.DeclaringType.TypeHandle);
    }

    static void Patch(byte[] b, int at, int value)
    {
        b[at] = (byte)value; b[at + 1] = (byte)(value >> 8); b[at + 2] = (byte)(value >> 16); b[at + 3] = (byte)(value >> 24);
    }

    /// <summary>Invokes a clone and unwraps TargetInvocationException.</summary>
    public static object Invoke(DynamicMethod dm, params object[] args)
    {
        try { return dm.Invoke(null, args); }
        catch (TargetInvocationException e) { throw e.InnerException; }
    }
}
