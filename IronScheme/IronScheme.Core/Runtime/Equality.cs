#region License
/* Copyright (c) 2007-2016 Llewellyn Pritchard
 * All rights reserved.
 * This source code is subject to terms and conditions of the BSD License.
 * See docs/license.txt. */
#endregion

using System;
using System.Reflection;
using System.Text;
using Oyster.Math;

namespace IronScheme.Core
{
  public partial class Builtins
  {
    // can't move this, gets inlined most of the time
    [Primitive("eq?", Flags = PrimitiveFlags.Pure, Inline = "eq?")]
    public static object IsEqual(object first, object second)
    {
      return GetBool(ReferenceEquals(first, second));
    }

    // can't move this, gets inlined most of the time
    [Primitive("eqv?", Flags = PrimitiveFlags.Pure, Inline = "eqv?")]
    public static object IsEqualValue(object first, object second)
    {
      if (first is Encoding && second is Encoding)
      {
        return GetBool(((Encoding) first).WebName == ((Encoding) second).WebName);
      }

      return GetBool(Equals(first, second));
    }
  }
}
