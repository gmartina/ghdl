--  Create declarations for synthesis.
--  Copyright (C) 2017 Tristan Gingold
--
--  This file is part of GHDL.
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 51 Franklin Street - Fifth Floor, Boston,
--  MA 02110-1301, USA.

with Types; use Types;
with Mutils; use Mutils;

with Netlists; use Netlists;
with Netlists.Builders; use Netlists.Builders;
with Netlists.Folds; use Netlists.Folds;
with Netlists.Utils; use Netlists.Utils;
with Netlists.Gates;

with Vhdl.Errors;
with Vhdl.Utils; use Vhdl.Utils;
with Vhdl.Std_Package;
with Vhdl.Ieee.Std_Logic_1164;

with Synth.Environment; use Synth.Environment;
with Synth.Expr; use Synth.Expr;
with Synth.Stmts;
with Synth.Source; use Synth.Source;
with Synth.Errors; use Synth.Errors;
with Synth.Files_Operations;

package body Synth.Decls is
   procedure Synth_Anonymous_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node);

   procedure Create_Var_Wire
     (Syn_Inst : Synth_Instance_Acc; Decl : Iir; Init : Value_Acc)
   is
      Val : constant Value_Acc := Get_Value (Syn_Inst, Decl);
      Value : Net;
      Ival : Net;
      W : Width;
      Name : Sname;
   begin
      case Val.Kind is
         when Value_Wire =>
            --  FIXME: get the width directly from the wire ?
            W := Get_Type_Width (Val.Typ);
            Name := New_Sname_User (Get_Identifier (Decl),
                                    Get_Sname (Syn_Inst));
            if Init /= null then
               Ival := Get_Net (Init);
               pragma Assert (Get_Width (Ival) = W);
               Value := Build_Isignal (Get_Build (Syn_Inst), Name, Ival);
            else
               Value := Build_Signal (Get_Build (Syn_Inst), Name, W);
            end if;
            Set_Location (Value, Decl);
            Set_Wire_Gate (Val.W, Value);
         when others =>
            raise Internal_Error;
      end case;
   end Create_Var_Wire;

   procedure Synth_Subtype_Indication_If_Anonymous
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) is
   begin
      if Get_Type_Declarator (Atype) = Null_Node then
         Synth_Subtype_Indication (Syn_Inst, Atype);
      end if;
   end Synth_Subtype_Indication_If_Anonymous;

   function Synth_Array_Type_Definition
     (Syn_Inst : Synth_Instance_Acc; Def : Node) return Type_Acc
   is
      El_Type : constant Node := Get_Element_Subtype (Def);
      Ndims : constant Natural := Get_Nbr_Dimensions (Def);
      El_Typ : Type_Acc;
      Typ : Type_Acc;
   begin
      Synth_Subtype_Indication_If_Anonymous (Syn_Inst, El_Type);
      El_Typ := Get_Value_Type (Syn_Inst, El_Type);

      if El_Typ.Kind in Type_Nets and then Ndims = 1 then
         Typ := Create_Unbounded_Vector (El_Typ);
      else
         Typ := Create_Unbounded_Array (Iir_Index32 (Ndims), El_Typ);
      end if;
      return Typ;
   end Synth_Array_Type_Definition;

   function Synth_Record_Type_Definition
     (Syn_Inst : Synth_Instance_Acc; Def : Node) return Type_Acc
   is
      El_List : constant Node_Flist := Get_Elements_Declaration_List (Def);
      Rec_Els : Rec_El_Array_Acc;
      El : Node;
      El_Typ : Type_Acc;
      Off : Uns32;
      Typ : Type_Acc;
   begin
      if not Is_Fully_Constrained_Type (Def) then
         return null;
      end if;
      Rec_Els := Create_Rec_El_Array
        (Iir_Index32 (Get_Nbr_Elements (El_List)));
      Typ := Create_Record_Type (Rec_Els, 0);

      Off := 0;
      for I in Flist_First .. Flist_Last (El_List) loop
         El := Get_Nth_Element (El_List, I);
         Synth_Declaration_Type (Syn_Inst, El);
         El_Typ := Get_Value_Type (Syn_Inst, Get_Type (El));
         Rec_Els.E (Iir_Index32 (I + 1)) := (Off => Off,
                                             Typ => El_Typ);
         Off := Off + Get_Type_Width (El_Typ);
      end loop;
      Typ.W := Off;

      return Typ;
   end Synth_Record_Type_Definition;

   function Synth_Access_Type_Definition
     (Syn_Inst : Synth_Instance_Acc; Def : Node) return Type_Acc
   is
      Des_Type : constant Node := Get_Designated_Type (Def);
      Des_Typ : Type_Acc;
      Typ : Type_Acc;
   begin
      Synth_Subtype_Indication_If_Anonymous (Syn_Inst, Des_Type);
      Des_Typ := Get_Value_Type (Syn_Inst, Des_Type);

      Typ := Create_Access_Type (Des_Typ);
      return Typ;
   end Synth_Access_Type_Definition;

   function Synth_File_Type_Definition
     (Syn_Inst : Synth_Instance_Acc; Def : Node) return Type_Acc
   is
      File_Type : constant Node := Get_Type (Get_File_Type_Mark (Def));
      File_Typ : Type_Acc;
      Typ : Type_Acc;
   begin
      File_Typ := Get_Value_Type (Syn_Inst, File_Type);

      Typ := Create_File_Type (File_Typ);
      return Typ;
   end Synth_File_Type_Definition;

   procedure Synth_Type_Definition (Syn_Inst : Synth_Instance_Acc; Def : Node)
   is
      Typ : Type_Acc;
   begin
      case Get_Kind (Def) is
         when Iir_Kind_Enumeration_Type_Definition =>
            if Def = Vhdl.Ieee.Std_Logic_1164.Std_Ulogic_Type
              or else Def = Vhdl.Ieee.Std_Logic_1164.Std_Logic_Type
            then
               Typ := Logic_Type;
            elsif Def = Vhdl.Std_Package.Boolean_Type_Definition then
               Typ := Boolean_Type;
            elsif Def = Vhdl.Std_Package.Bit_Type_Definition then
               Typ := Bit_Type;
            else
               declare
                  Nbr_El : constant Natural :=
                    Get_Nbr_Elements (Get_Enumeration_Literal_List (Def));
                  Rng : Discrete_Range_Type;
                  W : Width;
               begin
                  W := Uns32 (Clog2 (Uns64 (Nbr_El)));
                  Rng := (Dir => Iir_Downto,
                          Is_Signed => False,
                          Left => Int64 (Nbr_El - 1),
                          Right => 0);
                  Typ := Create_Discrete_Type (Rng, W);
               end;
            end if;
         when Iir_Kind_Array_Type_Definition =>
            Typ := Synth_Array_Type_Definition (Syn_Inst, Def);
         when Iir_Kind_Access_Type_Definition =>
            Typ := Synth_Access_Type_Definition (Syn_Inst, Def);
         when Iir_Kind_File_Type_Definition =>
            Typ := Synth_File_Type_Definition (Syn_Inst, Def);
         when Iir_Kind_Record_Type_Definition =>
            Typ := Synth_Record_Type_Definition (Syn_Inst, Def);
         when others =>
            Vhdl.Errors.Error_Kind ("synth_type_definition", Def);
      end case;
      if Typ /= null then
         Create_Object (Syn_Inst, Def, Create_Value_Subtype (Typ));
      end if;
   end Synth_Type_Definition;

   procedure Synth_Anonymous_Type_Definition
     (Syn_Inst : Synth_Instance_Acc; Def : Node; St : Node)
   is
      Typ : Type_Acc;
   begin
      case Get_Kind (Def) is
         when Iir_Kind_Integer_Type_Definition
           | Iir_Kind_Physical_Type_Definition =>
            declare
               Cst : constant Node := Get_Range_Constraint (St);
               L, R : Int64;
               Rng : Discrete_Range_Type;
               W : Width;
            begin
               L := Get_Value (Get_Left_Limit (Cst));
               R := Get_Value (Get_Right_Limit (Cst));
               Rng := Synth_Discrete_Range_Expression
                 (L, R, Get_Direction (Cst));
               W := Discrete_Range_Width (Rng);
               Typ := Create_Discrete_Type (Rng, W);
            end;
         when Iir_Kind_Floating_Type_Definition =>
            declare
               Cst : constant Node := Get_Range_Constraint (St);
               L, R : Fp64;
               Rng : Float_Range_Type;
            begin
               L := Get_Fp_Value (Get_Left_Limit (Cst));
               R := Get_Fp_Value (Get_Right_Limit (Cst));
               Rng := (Get_Direction (Cst), L, R);
               Typ := Create_Float_Type (Rng);
            end;
         when Iir_Kind_Array_Type_Definition =>
            Typ := Synth_Array_Type_Definition (Syn_Inst, Def);
         when others =>
            Vhdl.Errors.Error_Kind ("synth_anonymous_type_definition", Def);
      end case;
      Create_Object (Syn_Inst, Def, Create_Value_Subtype (Typ));
   end Synth_Anonymous_Type_Definition;

   function Synth_Discrete_Range_Constraint
     (Syn_Inst : Synth_Instance_Acc; Rng : Node) return Discrete_Range_Type
   is
      Res : Discrete_Range_Type;
   begin
      Synth_Discrete_Range (Syn_Inst, Rng, Res);
      return Res;
   end Synth_Discrete_Range_Constraint;

   function Synth_Float_Range_Constraint
     (Syn_Inst : Synth_Instance_Acc; Rng : Node) return Float_Range_Type is
   begin
      case Get_Kind (Rng) is
         when Iir_Kind_Range_Expression =>
            --  FIXME: check range.
            return Synth_Float_Range_Expression (Syn_Inst, Rng);
         when others =>
            Vhdl.Errors.Error_Kind ("synth_float_range_constraint", Rng);
      end case;
   end Synth_Float_Range_Constraint;

   function Synth_Array_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) return Type_Acc
   is
      El_Type : constant Node := Get_Element_Subtype (Atype);
      St_Indexes : constant Node_Flist := Get_Index_Subtype_List (Atype);
      Ptype : Node;
      St_El : Node;
      Btyp : Type_Acc;
      Etyp : Type_Acc;
      Bnds : Bound_Array_Acc;
   begin
      --  VHDL08
      if Get_Array_Element_Constraint (Atype) /= Null_Node
        or else
        (Get_Resolution_Indication (Atype) /= Null_Node
           and then
           (Get_Kind (Get_Resolution_Indication (Atype))
              = Iir_Kind_Array_Element_Resolution))
      then
         --  This subtype has created a new anonymous subtype for the
         --  element.
         Synth_Subtype_Indication (Syn_Inst, El_Type);
      end if;

      if not Get_Index_Constraint_Flag (Atype) then
         Ptype := Get_Type (Get_Subtype_Type_Mark (Atype));
         if Get_Element_Subtype (Ptype) = Get_Element_Subtype (Atype) then
            --  That's an alias.
            --  FIXME: maybe a resolution function was added?
            --  FIXME: also handle resolution added in element subtype.
            return Get_Value_Type (Syn_Inst, Ptype);
         end if;
      end if;

      Btyp := Get_Value_Type (Syn_Inst, Get_Base_Type (Atype));
      case Btyp.Kind is
         when Type_Unbounded_Vector =>
            if Get_Index_Constraint_Flag (Atype) then
               St_El := Get_Index_Type (St_Indexes, 0);
               return Create_Vector_Type
                 (Synth_Bounds_From_Range (Syn_Inst, St_El), Btyp.Uvec_El);
            else
               --  An alias.
               --  Handle vhdl08 definition of std_logic_vector from
               --  std_ulogic_vector.
               return Btyp;
            end if;
         when Type_Unbounded_Array =>
            --  FIXME: partially constrained arrays, subtype in indexes...
            Etyp := Get_Value_Type (Syn_Inst, El_Type);
            if Get_Index_Constraint_Flag (Atype) then
               Bnds := Create_Bound_Array
                 (Iir_Index32 (Get_Nbr_Elements (St_Indexes)));
               for I in Flist_First .. Flist_Last (St_Indexes) loop
                  St_El := Get_Index_Type (St_Indexes, I);
                  Bnds.D (Iir_Index32 (I + 1)) :=
                    Synth_Bounds_From_Range (Syn_Inst, St_El);
               end loop;
               return Create_Array_Type (Bnds, Etyp);
            else
               raise Internal_Error;
            end if;
         when others =>
            raise Internal_Error;
      end case;
   end Synth_Array_Subtype_Indication;

   function Synth_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) return Type_Acc is
   begin
      --  TODO: handle aliases directly.
      case Get_Kind (Atype) is
         when Iir_Kind_Array_Subtype_Definition =>
            return Synth_Array_Subtype_Indication (Syn_Inst, Atype);
         when Iir_Kind_Record_Subtype_Definition =>
            return Synth_Record_Type_Definition (Syn_Inst, Atype);
         when Iir_Kind_Integer_Subtype_Definition
           | Iir_Kind_Physical_Subtype_Definition
           | Iir_Kind_Enumeration_Subtype_Definition =>
            declare
               Btype : constant Type_Acc :=
                 Get_Value_Type (Syn_Inst, Get_Base_Type (Atype));
               Rng : Discrete_Range_Type;
               W : Width;
            begin
               if Btype.Kind in Type_Nets then
                  --  A subtype of a bit/logic type is still a bit/logic.
                  --  FIXME: bounds.
                  return Btype;
               else
                  Rng := Synth_Discrete_Range_Constraint
                    (Syn_Inst, Get_Range_Constraint (Atype));
                  W := Discrete_Range_Width (Rng);
                  return Create_Discrete_Type (Rng, W);
               end if;
            end;
         when Iir_Kind_Floating_Subtype_Definition =>
            declare
               Rng : Float_Range_Type;
            begin
               Rng := Synth_Float_Range_Constraint
                 (Syn_Inst, Get_Range_Constraint (Atype));
               return Create_Float_Type (Rng);
            end;
         when others =>
            Vhdl.Errors.Error_Kind ("synth_subtype_indication", Atype);
      end case;
   end Synth_Subtype_Indication;

   procedure Synth_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node)
   is
      Typ : Type_Acc;
   begin
      Typ := Synth_Subtype_Indication (Syn_Inst, Atype);
      pragma Assert (Typ /= null);
      Create_Object (Syn_Inst, Atype, Create_Value_Subtype (Typ));
   end Synth_Subtype_Indication;

   procedure Synth_Anonymous_Subtype_Indication
     (Syn_Inst : Synth_Instance_Acc; Atype : Node) is
   begin
      if Atype = Null_Node
        or else Get_Type_Declarator (Atype) /= Null_Node
      then
         return;
      end if;
      Synth_Subtype_Indication (Syn_Inst, Atype);
   end Synth_Anonymous_Subtype_Indication;

   pragma Unreferenced (Synth_Anonymous_Subtype_Indication);

   function Get_Declaration_Type (Decl : Node) return Node
   is
      Ind : constant Node := Get_Subtype_Indication (Decl);
      Atype : Node;
   begin
      if Ind = Null_Node then
         --  No subtype indication; use the same type.
         return Null_Node;
      end if;
      Atype := Ind;
      loop
         case Get_Kind (Atype) is
            when Iir_Kinds_Denoting_Name =>
               Atype := Get_Named_Entity (Atype);
            when Iir_Kind_Subtype_Declaration
              | Iir_Kind_Type_Declaration =>
               --  Type already declared, so already handled.
               return Null_Node;
            when Iir_Kind_Array_Subtype_Definition
              | Iir_Kind_Record_Subtype_Definition
              | Iir_Kind_Integer_Subtype_Definition
              | Iir_Kind_Floating_Subtype_Definition
              | Iir_Kind_Physical_Subtype_Definition
              | Iir_Kind_Enumeration_Subtype_Definition =>
               return Atype;
            when others =>
               Vhdl.Errors.Error_Kind ("get_declaration_type", Atype);
         end case;
      end loop;
   end Get_Declaration_Type;

   procedure Synth_Declaration_Type
     (Syn_Inst : Synth_Instance_Acc; Decl : Node)
   is
      Atype : constant Node := Get_Declaration_Type (Decl);
   begin
      if Atype = Null_Node then
         return;
      end if;
      Synth_Subtype_Indication (Syn_Inst, Atype);
   end Synth_Declaration_Type;

   procedure Synth_Constant_Declaration
     (Syn_Inst : Synth_Instance_Acc; Decl : Node)
   is
      Deferred_Decl : constant Node := Get_Deferred_Declaration (Decl);
      First_Decl : Node;
      Decl_Type : Node;
      Val : Value_Acc;
      Cst : Value_Acc;
      Obj_Type : Type_Acc;
   begin
      Synth_Declaration_Type (Syn_Inst, Decl);
      if Deferred_Decl = Null_Node
        or else Get_Deferred_Declaration_Flag (Decl)
      then
         --  Create the object (except for full declaration of a
         --  deferred constant).
         Create_Object (Syn_Inst, Decl, null);
      end if;
      --  Initialize the value (except for a deferred declaration).
      if Deferred_Decl = Null_Node then
         --  A normal constant declaration
         First_Decl := Decl;
      elsif not Get_Deferred_Declaration_Flag (Decl) then
         --  The full declaration of a deferred constant.
         First_Decl := Deferred_Decl;
      else
         --  The first declaration of a deferred constant.
         First_Decl := Null_Node;
      end if;
      if First_Decl /= Null_Node then
         --  Use the type of the declaration.  The type of the constant may
         --  be derived from the value.
         --  FIXME: what about multiple declarations ?
         Decl_Type := Get_Subtype_Indication (Decl);
         if Get_Kind (Decl_Type) in Iir_Kinds_Denoting_Name then
            --  Type mark.
            Decl_Type := Get_Type (Get_Named_Entity (Decl_Type));
         end if;
         Obj_Type := Get_Value_Type (Syn_Inst, Decl_Type);
         Val := Synth_Expression_With_Type
           (Syn_Inst, Get_Default_Value (Decl), Obj_Type);
         Val := Synth_Subtype_Conversion (Val, Obj_Type, True, Decl);
         --  For constant functions, the value must be constant.
         pragma Assert (not Get_Instance_Const (Syn_Inst)
                          or else Is_Static (Val));
         if Val.Kind = Value_Const then
            Cst := Val;
         else
            Cst := Create_Value_Const (Val, Decl);
         end if;
         Create_Object_Force (Syn_Inst, First_Decl, Cst);
      end if;
   end Synth_Constant_Declaration;

   procedure Synth_Attribute_Specification
     (Syn_Inst : Synth_Instance_Acc; Spec : Node)
   is
      Decl : constant Node := Get_Attribute_Designator (Spec);
      Value : Iir_Attribute_Value;
      Val : Value_Acc;
      Val_Type : Type_Acc;
   begin
      Val_Type := Get_Value_Type
        (Syn_Inst, Get_Type (Get_Named_Entity (Decl)));
      Value := Get_Attribute_Value_Spec_Chain (Spec);
      while Value /= Null_Iir loop
         --  2. The expression is evaluated to determine the value
         --     of the attribute.
         --     It is an error if the value of the expression does not
         --     belong to the subtype of the attribute; if the
         --     attribute is of an array type, then an implicit
         --     subtype conversion is first performed on the value,
         --     unless the attribute's subtype indication denotes an
         --     unconstrained array type.
         Val := Synth_Expression_With_Type
           (Syn_Inst, Get_Expression (Spec), Val_Type);
         --  Check_Constraints (Instance, Val, Attr_Type, Decl);

         --  3. A new instance of the designated attribute is created
         --     and associated with each of the affected items.
         --
         --  4. Each new attribute instance is assigned the value of
         --     the expression.
         Create_Object (Syn_Inst, Value, Val);
         --  Unshare (Val, Instance_Pool);

         Value := Get_Spec_Chain (Value);
      end loop;
   end Synth_Attribute_Specification;

   procedure Synth_Subprogram_Declaration
     (Syn_Inst : Synth_Instance_Acc; Subprg : Node)
   is
      Inter : Node;
   begin
      if Is_Second_Subprogram_Specification (Subprg) then
         --  Already handled.
         return;
      end if;

      Inter := Get_Interface_Declaration_Chain (Subprg);
      while Inter /= Null_Node loop
         Synth_Declaration_Type (Syn_Inst, Inter);
         Inter := Get_Chain (Inter);
      end loop;
   end Synth_Subprogram_Declaration;

   procedure Synth_Convertible_Declarations (Syn_Inst : Synth_Instance_Acc)
   is
      use Vhdl.Std_Package;
   begin
      Create_Object
        (Syn_Inst, Convertible_Integer_Type_Definition,
         Get_Value (Syn_Inst, Universal_Integer_Type_Definition));
      Create_Object
        (Syn_Inst, Convertible_Real_Type_Definition,
         Get_Value (Syn_Inst, Universal_Real_Type_Definition));
   end Synth_Convertible_Declarations;

   procedure Synth_Package_Declaration
     (Parent_Inst : Synth_Instance_Acc; Pkg : Node)
   is
      pragma Assert (not Is_Uninstantiated_Package (Pkg));
      Syn_Inst : Synth_Instance_Acc;
      Val : Value_Acc;
   begin
      Syn_Inst := Make_Instance (Parent_Inst, Pkg);
      Val := Create_Value_Instance (Syn_Inst);
      if Get_Kind (Get_Parent (Pkg)) = Iir_Kind_Design_Unit then
         --  Global package: in no particular order.
         Create_Package_Object (Parent_Inst, Pkg, Val);
      else
         --  Local package: check elaboration order.
         Create_Object (Parent_Inst, Pkg, Val);
      end if;
      Synth_Declarations (Syn_Inst, Get_Declaration_Chain (Pkg));
      if Pkg = Vhdl.Std_Package.Standard_Package then
         Synth_Convertible_Declarations (Syn_Inst);
      end if;
   end Synth_Package_Declaration;

   procedure Synth_Package_Body
     (Parent_Inst : Synth_Instance_Acc; Pkg : Node; Bod : Node)
   is
      Val : Value_Acc;
   begin
      if Get_Kind (Get_Parent (Pkg)) = Iir_Kind_Design_Unit then
         Val := Get_Package_Object (Parent_Inst, Pkg);
      else
         Val := Get_Value (Parent_Inst, Pkg);
      end if;
      Synth_Declarations (Get_Value_Instance (Val.Instance),
                          Get_Declaration_Chain (Bod));
   end Synth_Package_Body;

   procedure Synth_Declaration
     (Syn_Inst : Synth_Instance_Acc; Decl : Node; Is_Subprg : Boolean) is
   begin
      case Get_Kind (Decl) is
         when Iir_Kind_Variable_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
            declare
               Def : constant Iir := Get_Default_Value (Decl);
               --  Slot : constant Object_Slot_Type := Get_Info (Decl).Slot;
               Init : Value_Acc;
               Obj_Type : Type_Acc;
            begin
               Obj_Type := Get_Value_Type (Syn_Inst, Get_Type (Decl));
               if Is_Valid (Def) then
                  Init := Synth_Expression_With_Type (Syn_Inst, Def, Obj_Type);
                  Init := Synth_Subtype_Conversion
                    (Init, Obj_Type, False, Decl);
               else
                  Init := Create_Value_Default (Obj_Type);
               end if;
               if Get_Instance_Const (Syn_Inst) then
                  Create_Object (Syn_Inst, Decl, Unshare (Init, Current_Pool));
               else
                  Create_Wire_Object (Syn_Inst, Wire_Variable, Decl);
                  Create_Var_Wire (Syn_Inst, Decl, Init);
                  if Is_Subprg then
                     Phi_Assign
                       (Get_Build (Syn_Inst),
                        Get_Value (Syn_Inst, Decl).W, Get_Net (Init), 0);
                  end if;
               end if;
            end;
         when Iir_Kind_Interface_Variable_Declaration =>
            --  Ignore default value.
            Create_Wire_Object (Syn_Inst, Wire_Variable, Decl);
            Create_Var_Wire (Syn_Inst, Decl, null);
         when Iir_Kind_Constant_Declaration =>
            Synth_Constant_Declaration (Syn_Inst, Decl);
         when Iir_Kind_Signal_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
            declare
               Def : constant Iir := Get_Default_Value (Decl);
               --  Slot : constant Object_Slot_Type := Get_Info (Decl).Slot;
               Init : Value_Acc;
               Obj_Type : Type_Acc;
            begin
               Create_Wire_Object (Syn_Inst, Wire_Signal, Decl);
               if Is_Valid (Def) then
                  Obj_Type := Get_Value_Type (Syn_Inst, Get_Type (Decl));
                  Init := Synth_Expression_With_Type (Syn_Inst, Def, Obj_Type);
                  Init := Synth_Subtype_Conversion
                    (Init, Obj_Type, False, Decl);
               else
                  Init := null;
               end if;
               Create_Var_Wire (Syn_Inst, Decl, Init);
            end;
         when Iir_Kind_Object_Alias_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
            declare
               Obj : Value_Acc;
               Off : Uns32;
               Voff : Net;
               Rdwd : Width;
               Typ : Type_Acc;
               Res : Value_Acc;
               Obj_Type : Type_Acc;
            begin
               Obj_Type := Get_Value_Type (Syn_Inst, Get_Type (Decl));
               Stmts.Synth_Assignment_Prefix (Syn_Inst, Get_Name (Decl),
                                              Obj, Off, Voff, Rdwd, Typ);
               pragma Assert (Voff = No_Net);
               if Obj.Kind = Value_Net then
                  --  Object is a net if it is not writable.  Extract the
                  --  bits for the alias.
                  Res := Create_Value_Net
                    (Build2_Extract (Get_Build (Syn_Inst), Obj.N, Off, Typ.W),
                     Typ);
               else
                  Res := Create_Value_Alias (Obj, Off, Typ);
               end if;
               Res := Synth_Subtype_Conversion (Res, Obj_Type, True, Decl);
               Create_Object (Syn_Inst, Decl, Res);
            end;
         when Iir_Kind_Anonymous_Signal_Declaration =>
            --  Anonymous signals created by inertial associations are
            --  simply ignored.
            null;
         when Iir_Kind_Procedure_Declaration
           | Iir_Kind_Function_Declaration =>
            Synth_Subprogram_Declaration (Syn_Inst, Decl);
         when Iir_Kind_Procedure_Body
           | Iir_Kind_Function_Body =>
            null;
         when Iir_Kind_Non_Object_Alias_Declaration =>
            null;
         when Iir_Kind_Attribute_Declaration =>
            --  Nothing to do: the type is a type_mark, not a subtype
            --  indication.
            null;
         when Iir_Kind_Attribute_Specification =>
            Synth_Attribute_Specification (Syn_Inst, Decl);
         when Iir_Kind_Type_Declaration =>
            Synth_Type_Definition (Syn_Inst, Get_Type_Definition (Decl));
         when Iir_Kind_Anonymous_Type_Declaration =>
            Synth_Anonymous_Type_Definition
              (Syn_Inst, Get_Type_Definition (Decl),
               Get_Subtype_Definition (Decl));
         when  Iir_Kind_Subtype_Declaration =>
            Synth_Declaration_Type (Syn_Inst, Decl);
         when Iir_Kind_Component_Declaration =>
            null;
         when Iir_Kind_File_Declaration =>
            declare
               F : File_Index;
               Res : Value_Acc;
               Obj_Typ : Type_Acc;
            begin
               F := Synth.Files_Operations.Elaborate_File_Declaration
                 (Syn_Inst, Decl);
               Obj_Typ := Get_Value_Type (Syn_Inst, Get_Type (Decl));
               Res := Create_Value_File (Obj_Typ, F);
               Create_Object (Syn_Inst, Decl, Res);
            end;
         when Iir_Kind_Psl_Default_Clock =>
            --  Ignored; directly used by PSL directives.
            null;
         when Iir_Kind_Use_Clause =>
            null;
         when others =>
            Vhdl.Errors.Error_Kind ("synth_declaration", Decl);
      end case;
   end Synth_Declaration;

   procedure Synth_Declarations
     (Syn_Inst : Synth_Instance_Acc; Decls : Iir; Is_Subprg : Boolean := False)
   is
      Decl : Iir;
   begin
      Decl := Decls;
      while Is_Valid (Decl) loop
         Synth_Declaration (Syn_Inst, Decl, Is_Subprg);

         Decl := Get_Chain (Decl);
      end loop;
   end Synth_Declarations;

   procedure Finalize_Signal (Syn_Inst : Synth_Instance_Acc; Decl : Node)
   is
      use Netlists.Gates;
      Val : Value_Acc;
      Gate_Net : Net;
      Gate : Instance;
      Drv : Net;
      Def_Val : Net;
   begin
      Val := Get_Value (Syn_Inst, Decl);
      Gate_Net := Get_Wire_Gate (Val.W);
      Gate := Get_Net_Parent (Gate_Net);
      case Get_Id (Gate) is
         when Id_Signal =>
            Drv := Get_Input_Net (Gate, 0);
            Def_Val := No_Net;
         when Id_Isignal =>
            Drv := Get_Input_Net (Gate, 0);
            Def_Val := Get_Input_Net (Gate, 1);
         when others =>
            --  Todo: output ?
            raise Internal_Error;
      end case;
      if Drv = No_Net then
         if Def_Val = No_Net then
            Warning_Msg_Synth
              (+Decl, "%n is never assigned and has no default value",
               (1 => +Decl));
         else
            Warning_Msg_Synth (+Decl, "%n is never assigned", (1 => +Decl));
            Connect (Get_Input (Gate, 0), Def_Val);
         end if;
      end if;

      Free_Wire (Val.W);
   end Finalize_Signal;

   procedure Finalize_Declaration
     (Syn_Inst : Synth_Instance_Acc; Decl : Node; Is_Subprg : Boolean) is
   begin
      case Get_Kind (Decl) is
         when Iir_Kind_Variable_Declaration
           | Iir_Kind_Interface_Variable_Declaration =>
            if not Get_Instance_Const (Syn_Inst) then
               declare
                  Val : constant Value_Acc := Get_Value (Syn_Inst, Decl);
               begin
                  Free_Wire (Val.W);
               end;
            end if;
         when Iir_Kind_Constant_Declaration =>
            null;
         when Iir_Kind_Signal_Declaration =>
            pragma Assert (not Is_Subprg);
            Finalize_Signal (Syn_Inst, Decl);
         when Iir_Kind_Anonymous_Signal_Declaration =>
            null;
         when Iir_Kind_Object_Alias_Declaration =>
            null;
         when Iir_Kind_Procedure_Declaration
           | Iir_Kind_Function_Declaration =>
            null;
         when Iir_Kind_Procedure_Body
           | Iir_Kind_Function_Body =>
            null;
         when Iir_Kind_Non_Object_Alias_Declaration =>
            null;
         when Iir_Kind_Attribute_Declaration =>
            null;
         when Iir_Kind_Attribute_Specification =>
            null;
         when Iir_Kind_Type_Declaration =>
            null;
         when Iir_Kind_Anonymous_Type_Declaration =>
            null;
         when  Iir_Kind_Subtype_Declaration =>
            null;
         when Iir_Kind_Component_Declaration =>
            null;
         when Iir_Kind_File_Declaration =>
            null;
         when Iir_Kind_Psl_Default_Clock =>
            --  Ignored; directly used by PSL directives.
            null;
         when others =>
            Vhdl.Errors.Error_Kind ("finalize_declaration", Decl);
      end case;
   end Finalize_Declaration;

   procedure Finalize_Declarations (Syn_Inst : Synth_Instance_Acc;
                                    Decls : Iir;
                                    Is_Subprg : Boolean := False)
   is
      Decl : Iir;
   begin
      Decl := Decls;
      while Is_Valid (Decl) loop
         Finalize_Declaration (Syn_Inst, Decl, Is_Subprg);

         Decl := Get_Chain (Decl);
      end loop;
   end Finalize_Declarations;
end Synth.Decls;
