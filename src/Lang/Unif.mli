(* This file is part of DBL, released under MIT license.
 * See LICENSE for details.
 *)

(** The Unif language: result of type-inference.
  The main feature of the Unif language is a support for type-unification *)

(* Author: Piotr Polesiuk, 2023,2024 *)

include module type of SyntaxNode.Export

(** Kind unification variable *)
type kuvar

(** Kinds.

  This is an abstract type. Use [Kind.view] to view it. *)
type kind

(** Names of implicit parameters *)
type name = string

(** Unification variables *)
type uvar

(** Type variables *)
type tvar

(** Scope of a type *)
type scope

(** Types.

  This is an abstract type. Use [Type.view] to view it. *)
type typ

(** Effects. They are represented as types effect kind *)
type effect = typ

(** Polymorphic type scheme *)
type scheme = {
  sch_tvars    : tvar list;
    (** universally quantified type variables *)

  sch_implicit : (name * scheme) list;
    (** Implicit parameters *)
  
  sch_body     : typ
    (** Body of the type scheme *)
}

(** Type substitution *)
type subst

(** Declaration of an ADT constructor *)
type ctor_decl = {
  ctor_name        : string;
    (** Name of the constructor *)

  ctor_tvars       : tvar list;
    (** Existential type variables of the constructor *)

  ctor_implicit    : (name * scheme) list;
    (** Implicit parameters of the constructor *)

  ctor_arg_schemes : scheme list
    (** Type schemes of the regular parameters *)
}

(* ========================================================================= *)
(** Variable *)
type var = Var.t

(** Pattern *)
type pattern = pattern_data node
and pattern_data =
  | PWildcard
    (** Wildcard pattern -- it matches everything *)

  | PVar of var * scheme
    (** Pattern that binds a variable of given scheme *)

  | PCtor of string * int * expr * ctor_decl list * tvar list * pattern list
    (** ADT constructor pattern. It stores a name, constructor index,
      proof that matched type is an ADT, full list of constructor of an ADT,
      existential type binders, and patterns for parameters. *)

(** Expression *)
and expr = expr_data node
and expr_data =
  | EUnit
    (** Unit expression *)

  | EVar of var
    (** Variable *)

  | EPureFn of var * scheme * expr
    (** Pure lambda-abstraction *)

  | EFn of var * scheme * expr
    (** Impure lambda-abstraction *)

  | ETFun of tvar * expr
    (** Type function *)

  | EApp of expr * expr
    (** Function application *)

  | ETApp of expr * typ
    (** Type application *)

  | ELet of var * scheme * expr * expr
    (** Let-definition *)

  | ECtor of expr * int * typ list * expr list
    (** Fully-applied constructor of ADT. The meaning of the parameters
      is the following.
      - Computationally irrelevant proof that given that the type of the
        whole expression is an ADT.
      - An index of the constructor.
      - Existential type parameters of the constructor.
      - Regular parameter of the constructor, including named and implicit. *)

  | EData of tvar * var * tvar list * ctor_decl list * expr
    (** Definition of an ADT. It binds type variable (defined type) and
      computationally irrelevant variable (the proof that the type is an
      ADT) *)

  | EMatch of expr * match_clause list * typ * effect
    (** Pattern-matching. It stores type and effect of the whole expression. *)

  | EHandle of tvar * var * expr * h_expr * typ * effect
    (** Handler. It stores handled (abstract) effect, capability variable,
      handled expression, handler body, and type and effect of the whole
      handler expression *)

  | ERepl of (unit -> expr) * effect
    (** REPL. It is a function that prompts user for another input. It returns
      an expression to evaluate, usually containing another REPL expression.
      This constructor stores also an effect of a REPL expression. *)

  | EReplExpr of expr * string * expr
    (** Print type (second parameter), evaluate and print the first expression,
      then continue to the second expression. *)

(** Clause of a pattern matching *)
and match_clause = pattern * expr

(** Handler expressions *)
and h_expr = h_expr_data node
and h_expr_data =
  | HEffect of typ * typ * var * var * expr
    (** Handler of effectful functional operation. It stores input type,
      output type, formal parameter, resumption formal parameter, and the
      body. *)

(** Program *)
type program = expr

(* ========================================================================= *)
(** Operations on kind unification variables *)
module KUVar : sig

  (** Check for equality *)
  val equal : kuvar -> kuvar -> bool

  (** Set a unification variable *)
  val set : kuvar -> kind -> unit
end

(* ========================================================================= *)
(** Operations on kinds *)
module Kind : sig
  (** View of kinds *)
  type kind_view =
    | KType
      (** Kind of all types *)

    | KEffect
      (** Kind of all effects *)
    
    | KClEffect
      (** Kind of all simple effects: only closed rows without unification
        variables *)

    | KUVar of kuvar
      (** Unification variable *)

    | KArrow of kind * kind
      (** Arrow kind *)

  (** Kind of all types *)
  val k_type : kind

  (** Kind of all effects *)
  val k_effect : kind

  (** Kind of all simple (closed) effects. These effects cannot contain
    unification variables. *)
  val k_cleffect : kind

  (** Arrow kind *)
  val k_arrow : kind -> kind -> kind

  (** Create an arrow kind with multiple parameters. *)
  val k_arrows : kind list -> kind -> kind

  (** Create a fresh unification kind variable *)
  val fresh_uvar : unit -> kind

  (** Reveal a top-most constructor of a kind *)
  val view : kind -> kind_view

  (** Check if given kind contains given unification variable *)
  val contains_uvar : kuvar -> kind -> bool
end

(* ========================================================================= *)
(** Operations on type variables *)
module TVar : sig
  (** Kind of a type variable *)
  val kind : tvar -> kind

  (** Create fresh type variable of given kind *)
  val fresh : kind -> tvar

  (** Check type variables for equality *)
  val equal : tvar -> tvar -> bool

  (** Finite sets of type variables *)
  module Set : Set.S with type elt = tvar

  (** Finite map from type variables *)
  module Map : Map.S with type key = tvar

  (** Finite partial permutations of type variables *)
  module Perm : Perm.S with type key = tvar and module KeySet = Set
end

(* ========================================================================= *)
(** Operations on scopes of types *)
module Scope : sig
  (** Initial scope *)
  val initial : scope

  (** Extend scope with a variable *)
  val add : scope -> tvar -> scope
end

(* ========================================================================= *)
(** Operations on unification variables *)
module UVar : sig
  type t = uvar

  (** Check unification variables for equality *)
  val equal : t -> t -> bool

  (** Set a unification variable, without checking any constraints. It returns
    expected scope of set type. The first parameter is a permutation attached
    to the unification variable. *)
  val raw_set : TVar.Perm.t -> t -> typ -> scope

  (** Promote unification variable to fresh type variable *)
  val fix : t -> tvar

  (** Shrink scope of given unification variable, leaving only those variables
    which satisfy given predicate *)
  val filter_scope : t -> (tvar -> bool) -> unit

  (** Set of unification variables *)
  module Set : Set.S with type elt = t
end

(* ========================================================================= *)
(** Operations on types *)
module Type : sig
  (** End of an effect *)
  type effect_end =
    | EEClosed
      (** Closed effect *)
    
    | EEUVar of TVar.Perm.t * uvar
      (** Open effect with unification variable at the end. The unification
        variable is associated with a delayed partial permutation of type
        variables. *)

    | EEVar of tvar
      (** Open effect with type variable at the end *)

    | EEApp of typ * typ
      (** Type application of an effect kind *)

  (** View of a type *)
  type type_view =
    | TUnit
      (** Unit type *)

    | TUVar of TVar.Perm.t * uvar
      (** Unification variable, associated with a delayed partial permutation,
      of type variables. Mappings of variables not in scope of the
      unification variable might be not present in the permutation. *)

    | TVar of tvar
      (** Regular type variable *)

    | TEffect of TVar.Set.t * effect_end
      (** Effect: a set of simple effect variables together with a way of
        closing an effect *)

    | TPureArrow of scheme * typ
      (** Pure arrow, i.e., type of function that doesn't perform any effects
        and always terminate *)

    | TArrow of scheme * typ * effect
      (** Impure arrow *)
  
    | TApp of typ * typ
      (** Type application *)

  (** Unit type *)
  val t_unit : typ

  (** Unification variable *)
  val t_uvar : TVar.Perm.t -> uvar -> typ

  (** Regular type variable *)
  val t_var : tvar -> typ

  (** Pure arrow type *)
  val t_pure_arrow : scheme -> typ -> typ

  (** Pure arrow, that takes multiple arguments *)
  val t_pure_arrows : scheme list -> typ -> typ

  (** Arrow type *)
  val t_arrow : scheme -> typ -> effect -> typ

  (** Create an effect *)
  val t_effect : TVar.Set.t -> effect_end -> effect

  (** Create a closed effect *)
  val t_closed_effect : TVar.Set.t -> effect

  (** Type application *)
  val t_app : typ -> typ -> typ

  (** Type application to multiple arguments *)
  val t_apps : typ -> typ list -> typ

  (** Fresh unification variable (packed as type) *)
  val fresh_uvar : scope:scope -> kind -> typ

  (** Reveal a top-most constructor of a type *)
  val view : typ -> type_view

  (** Reveal a representation of an effect: a set of effect variables together
    with a way of closing an effect. *)
  val effect_view : effect -> TVar.Set.t * effect_end

  (** Get the kind of given type *)
  val kind : typ -> kind

  (** Returns subtype of given type, where all closed rows on negative
    positions are opened by a fresh unification variable. It works only
    for proper types (of kind type) *)
  val open_down : scope:scope -> typ -> typ

  (** Returns supertype of given type, where all closed rows on positive
    positions are opened by a fresh unification variable. It works only
    for proper types (of kind type) *)
  val open_up : scope:scope -> typ -> typ

  (** Check if given unification variable appears in given type. It is
    equivalent to [UVar.mem u (uvars tp)], but faster. *)
  val contains_uvar : uvar -> typ -> bool

  (** Set of unification variables in given type *)
  val uvars : typ -> UVar.Set.t

  (** Extend given set of unification variables by unification variables
    from given type. Equivalent to [uvars tp UVar.Set.empty] *)
  val collect_uvars : typ -> UVar.Set.t -> UVar.Set.t

  (** Apply substitution to a type *)
  val subst : subst -> typ -> typ

  (** Ensure that given type fits given scope. It changes scope constraints
    of unification variables accordingly. On error, it returns escaping type
    variable. *)
  val try_shrink_scope : scope:scope -> typ -> (unit, tvar) result
end

(* ========================================================================= *)
(** Operations on effects *)
module Effect : sig
  (** View of effect *)
  type effect_view =
    | EffPure
      (** Pure effect *)

    | EffUVar of TVar.Perm.t * uvar
      (** Row unification variable (with delayed permutation) *)

    | EffVar  of tvar
      (** Row variable *)

    | EffApp  of typ * typ
      (** Type application of an effect kind *)

    | EffCons of tvar * effect
      (** Consing an simple effect variable to an effect *)

  (** Pure effect row *)
  val pure : effect

  (** Effect with single simple effect variable *)
  val singleton : tvar -> effect

  (** Effect with single IO effect *)
  val io : effect

  (** Consing a simple effect variable to an effect *)
  val cons : tvar -> effect -> effect

  (** Row-like view of an effect *)
  val view : effect -> effect_view

  (** View the end of given effect row. This function never returns value
    constructed by [EffCons] constructor *)
  val view_end : effect -> Type.effect_end

  (** Check if an effect is pure *)
  val is_pure : effect -> bool
end

(* ========================================================================= *)
(** Type substitutions *)
module Subst : sig
  (** Empty substitution *)
  val empty : subst

  (** Extend substitution with a renaming. The new version of a variable
    must be fresh enough. *)
  val rename_to_fresh : subst -> tvar -> tvar -> subst

  (** Extend substitution. It is rather parallel extension than composition *)
  val add_type : subst -> tvar -> typ -> subst
end

(* ========================================================================= *)
(** Operations on type schemes *)
module Scheme : sig
  (** Create a monomorphic type-scheme *)
  val of_type : typ -> scheme

  (** Set of unification variables in given scheme *)
  val uvars : scheme -> UVar.Set.t

  (** Extend given set of unification variables by unification variables
    from given scheme. Equivalent to [uvars sch UVar.Set.empty] *)
  val collect_uvars : scheme -> UVar.Set.t -> UVar.Set.t

  (** Make sure that type variables bound by this scheme are fresh *)
  val refresh : scheme -> scheme

  (** Apply substitution to a scheme *)
  val subst : subst -> scheme -> scheme
end

(* ========================================================================= *)
(** Operations on constructor declarations *)
module CtorDecl : sig
  (** Set of unification variables in given scheme *)
  val subst : subst -> ctor_decl -> ctor_decl
end
