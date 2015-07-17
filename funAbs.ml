

open Batteries
open Type

module VarMap = Hashtbl.Make(Utils.Varinfo)
module LocMap = Hashtbl.Make(Utils.Location)

(* TODO: Store the Cil.fundec too *)
(* THINK: Local variables have monomorphic shape schemes... so we could simplify this as vars : shape VarMap.t *)
type t = {
	vars : shape scheme VarMap.t;
	locs : E.t LocMap.t
}

(* TODO: no_vars = formals + locals
         no_locs ~ no_stmts ?
 *)
let create () =
	{ vars = VarMap.create 11
	; locs = LocMap.create 71
	}

let add_var tbl x sch =
	VarMap.replace tbl.vars x sch

let add_vars tbl =
	List.iter (fun (x,sch) -> add_var tbl x sch)

let add_loc tbl loc eff =
	Log.debug "Loc -> effects:\n %s -> %s\n"
		   (Utils.Location.to_string loc)
		   (Effects.to_string eff);
	LocMap.modify_def eff loc (fun f -> E.(eff + f)) tbl.locs

let fv_of tbl =
	let fv1 = VarMap.fold (fun _ sch fvs ->
		Vars.(Scheme.fv_of sch + fvs)
	) tbl.vars Vars.none
	in
	LocMap.fold (fun _ ef fvs ->
		Vars.(Effects.fv_of ef + fvs)
	) tbl.locs fv1

let map_inplace f g tbl =
	VarMap.map_inplace f tbl.vars;
	LocMap.map_inplace g tbl.locs

let zonk = map_inplace
	(fun _x -> Scheme.zonk)
	(fun _loc -> Effects.zonk)

let finalize = map_inplace
	(fun _x -> Scheme.zonk)
	(fun _loc -> Effects.(principal % zonk))

let shape_of tbl =
	VarMap.find tbl.vars

let regions_of tbl = Scheme.regions_in % shape_of tbl

let regions_of_list tbl = Regions.sum % List.map (regions_of tbl)

let effect_of tbl =
	LocMap.find tbl.locs

let sum tbl =
	LocMap.fold (fun _ ef acc -> E.(ef + acc)) tbl.locs E.none

(* TODO: should be cached *)
let effect_of_local_decl tbl fd :E.t =
	let open Cil in
	List.fold_left E.(fun fs x -> effect_of tbl x.vdecl + fs)
		E.none
		fd.slocals

let uninit_locals tbl fd :Regions.t =
	let open Effects in
	effect_of_local_decl tbl fd
		 |> filter is_uninits
		 |> regions

let aliased _ _ = Error.not_implemented()

let points_to _ _ = Error.not_implemented()

let pp_vars =
	(* THINK: mostly duplicated from Env.pp, refactor? *)
	let pp_binding (x,sch) =
		let loc = Cil.(x.vdecl) in
		let n = Cil.(x.vname) in
		loc, PP.(!^ n ++ colon ++ Shape.pp sch.body)
	in
	Utils.Location.pp_with_loc %
		PP.(List.map pp_binding % List.of_enum % VarMap.enum)

let pp_locs =
	let pp_binding (l,f) =
		l, PP.(space + !^ "->" ++ Effects.pp f)
	in
	Utils.Location.pp_with_loc %
		PP.(List.map pp_binding % List.of_enum % LocMap.enum)

let pp tbl =
	let vars_doc = pp_vars tbl.vars in
	let locs_doc = pp_locs tbl.locs in
	PP.(vars_doc + newline + locs_doc)

let to_string = PP.to_string % pp
