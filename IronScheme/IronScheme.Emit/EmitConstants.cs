using System;
using System.Reflection;
using System.Reflection.Emit;

namespace IronScheme.Emit
{
  // 常量表（04 §3）：编码成 fasl 后以 base64 字符串放进类型 "$Constants" 的类型初始化器，
  // 运行时 IronScheme.Core.Fasl.ReadTable 读回 object[] 存入静态字段 c；ldconst k 即 c[k]。
  // 用字符串而不是托管资源：内存模式（eval）的程序集不能带资源，两种模式因此一致。
  public sealed partial class LcilEmitter
  {
    public const string ConstantsTypeName = "$Constants";

    TypeBuilder constantsType;
    object[] live;

    void DefineConstants()
    {
      if (types.ContainsKey(ConstantsTypeName)) throw new LcilException($"{asm.File}: type name {ConstantsTypeName} is reserved");
      var core = LoadReference("IronScheme.Core");
      constantsType = module.DefineType(ConstantsTypeName, TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed | TypeAttributes.Class);
      constantsField = constantsType.DefineField("c", typeof(object[]), FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.InitOnly);
      types[ConstantsTypeName] = constantsType;              // Lcil 中可写 (ldsfld "$Constants" "c")
      fields[(ConstantsTypeName, "c")] = (FieldBuilder)constantsField;
      var il = constantsType.DefineTypeInitializer().GetILGenerator();
      if (live != null)
      {
        // 内存模式的活常量：登记到 ConstantPool，类型初始化器按编号取回
        int id = (int)core.GetType("IronScheme.Core.ConstantPool", true).GetMethod("Register").Invoke(null, new object[] { live });
        il.Emit(OpCodes.Ldc_I4, id);
        il.Emit(OpCodes.Call, core.GetType("IronScheme.Core.ConstantPool", true).GetMethod("Take"));
      }
      else
      {
        var bytes = FaslEncoder.EncodeTable(asm.Constants, asm.File);
        il.Emit(OpCodes.Ldstr, Convert.ToBase64String(bytes));
        il.Emit(OpCodes.Call, core.GetType("IronScheme.Core.Fasl", true).GetMethod("ReadTable", new[] { typeof(string) }));
      }
      il.Emit(OpCodes.Stsfld, constantsField);
      il.Emit(OpCodes.Ret);
    }
  }
}
