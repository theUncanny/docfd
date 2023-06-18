open Docfd_lib
open Lwd_infix

module Vars = struct
  let index_of_document_selected = Lwd.var 0

  let index_of_search_result_selected = Lwd.var 0

  let search_field = Lwd.var Ui_base.empty_search_field

  let search_field_focus_handle = Nottui.Focus.make ()
end

let set_document_selected ~choice_count n =
  let n = Misc_utils.bound_selection ~choice_count n in
  Lwd.set Vars.index_of_document_selected n;
  Lwd.set Vars.index_of_search_result_selected 0

let reset_document_selected () =
  Lwd.set Vars.index_of_document_selected 0;
  Lwd.set Vars.index_of_search_result_selected 0

let set_search_result_selected ~choice_count n =
  let n = Misc_utils.bound_selection ~choice_count n in
  Lwd.set Vars.index_of_search_result_selected n

let reload_document (doc : Document.t) =
  match doc.path with
  | None -> ()
  | Some path -> (
      match Document.of_path ~env:(Ui_base.eio_env ()) path with
      | Ok doc -> (
          reset_document_selected ();
          let document_store =
            Lwd.peek Ui_base.Vars.document_store
            |> Document_store.add_document doc
          in
          Lwd.set Ui_base.Vars.document_store document_store;
        )
      | Error _ -> ()
    )

let reload_document_selected
    ~(document_info_s : Document_store.value array)
  : unit =
  if Array.length document_info_s > 0 then (
    let index = Lwd.peek Vars.index_of_document_selected in
    let doc, _search_results = document_info_s.(index) in
    reload_document doc;
  )

let update_search_phrase () =
  reset_document_selected ();
  let search_phrase =
    Search_phrase.make
      ~fuzzy_max_edit_distance:!Params.max_fuzzy_edit_distance
      ~phrase:(fst @@ Lwd.peek Vars.search_field)
  in
  let document_store =
    Lwd.peek Ui_base.Vars.document_store
    |> Document_store.update_search_phrase search_phrase
  in
  Lwd.set Ui_base.Vars.document_store document_store

module Top_pane = struct
  module Document_list = struct
    let render_document_preview
        ~(document_info : Document_store.value)
        ~selected
      : Notty.image =
      let open Notty in
      let open Notty.Infix in
      let (doc, search_results) = document_info in
      let search_result_score_image =
        if !Params.debug then (
          if Array.length search_results = 0 then
            I.empty
          else (
            let x = search_results.(0) in
            I.strf "(best content search result score: %f)" (Search_result.score x)
          )
        ) else (
          I.empty
        )
      in
      let preview_line_images =
        let line_count =
          min Params.preview_line_count (Index.global_line_count doc.index)
        in
        OSeq.(0 --^ line_count)
        |> Seq.map (fun global_line_num -> Index.line_of_global_line_num global_line_num doc.index)
        |> Seq.map (fun line ->
            (I.string A.(bg lightgreen) " ")
            <|>
            (I.strf " %s" line)
          )
        |> List.of_seq
      in
      let preview_image =
        I.vcat preview_line_images
      in
      let path_image =
        I.string A.(fg lightgreen) "@ "
        <|>
        I.string A.empty
          (Option.value ~default:Params.stdin_doc_path_placeholder doc.path);
      in
      let title =
        Option.value ~default:"" doc.title
      in
      if selected then (
        (I.string A.(fg lightblue ++ st bold) title)
        <->
        (I.string A.empty "  "
         <|>
         I.vcat
           [ search_result_score_image;
             path_image;
             preview_image;
           ]
        )
      ) else (
        (I.string A.(fg lightblue) title)
        <->
        (I.string A.empty "  "
         <|>
         I.vcat
           [ search_result_score_image;
             path_image;
             preview_image;
           ]
        )
      )

    let main
        ~(document_info_s : Document_store.value array)
        ~(document_selected : int)
      : Nottui.ui Lwd.t =
      let document_count = Array.length document_info_s in
      let pane =
        if document_count = 0 then (
          Nottui.Ui.empty
        ) else (
          let (_term_width, term_height) = Notty_unix.Term.size (Ui_base.term ()) in
          CCInt.range'
            document_selected
            (min (document_selected + term_height / 2) document_count)
          |> CCList.of_iter
          |> List.map (fun j ->
              let selected = Int.equal document_selected j in
              render_document_preview ~document_info:document_info_s.(j) ~selected
            )
          |> List.map Nottui.Ui.atom
          |> Nottui.Ui.vcat
        )
      in
      Nottui.Ui.join_z (Ui_base.full_term_sized_background ()) pane
      |> Nottui.Ui.mouse_area
        (Ui_base.mouse_handler
           ~choice_count:document_count
           ~current_choice:Vars.index_of_document_selected)
      |> Lwd.return
  end

  module Right_pane = struct
    let main
        ~(document_info_s : Document_store.value array)
        ~(document_selected : int)
      : Nottui.ui Lwd.t =
      if Array.length document_info_s = 0 then
        Nottui_widgets.(v_pane empty_lwd empty_lwd)
      else (
        let$* search_result_selected = Lwd.get Vars.index_of_search_result_selected in
        let document_info = document_info_s.(document_selected) in
        Nottui_widgets.v_pane
          (Ui_base.Content_view.main ~document_info ~search_result_selected)
          (Ui_base.Search_result_list.main
             ~document_info
             ~index_of_search_result_selected:Vars.index_of_search_result_selected)
      )
  end

  let main
      ~(document_info_s : Document_store.value array)
    : Nottui.ui Lwd.t =
    let$* document_selected = Lwd.get Vars.index_of_document_selected in
    Nottui_widgets.h_pane
      (Document_list.main ~document_info_s ~document_selected)
      (Right_pane.main ~document_info_s ~document_selected)
end

module Bottom_pane = struct
  let status_bar
      ~(document_info_s : Document_store.value array)
      ~(input_mode : Ui_base.input_mode)
    =
    let$ index_of_document_selected = Lwd.get Vars.index_of_document_selected in
    let document_count = Array.length document_info_s in
    let input_mode_image =
      List.assoc input_mode Ui_base.Status_bar.input_mode_images
    in
    let content =
      if document_count = 0 then
        Nottui.Ui.atom input_mode_image
      else (
        let file_shown_count =
          Notty.I.strf ~attr:Ui_base.Status_bar.attr
            "%5d/%d documents listed"
            document_count !Ui_base.Vars.total_document_count
        in
        let index_of_selected =
          Notty.I.strf ~attr:Ui_base.Status_bar.attr
            "index of document selected: %d"
            index_of_document_selected
        in
        Notty.I.hcat
          [
            List.assoc input_mode Ui_base.Status_bar.input_mode_images;
            Ui_base.Status_bar.element_spacer;
            file_shown_count;
            Ui_base.Status_bar.element_spacer;
            index_of_selected;
          ]
        |> Nottui.Ui.atom
      )
    in
    Nottui.Ui.join_z (Ui_base.Status_bar.background_bar ()) content

  module Key_binding_info = struct
    let grid_contents : Ui_base.Key_binding_info.grid_contents =
      let open Ui_base.Key_binding_info in
      let navigate_grid =
        [
          [
            { label = "Enter"; msg = "open document" };
            { label = "/"; msg = "switch to search mode" };
            { label = "x"; msg = "clear search" };
          ];
          [
            { label = "Tab";
              msg = "switch to single file view" };
            { label = "r"; msg = "reload document selected" };
            { label = "q"; msg = "exit" };
          ];
        ]
      in
      let search_grid =
        [
          [
            { label = "Enter"; msg = "confirm and exit search mode" };
          ];
          [
            { label = ""; msg = "" };
          ];
        ]
      in
      [
        ({ input_mode = Navigate; init_ui_mode = Ui_multi_file },
         navigate_grid
        );
        ({ input_mode = Navigate; init_ui_mode = Ui_single_file },
         navigate_grid
        );
        ({ input_mode = Search; init_ui_mode = Ui_multi_file },
         search_grid
        );
        ({ input_mode = Search; init_ui_mode = Ui_single_file },
         search_grid
        );
      ]

    let grid_lookup = Ui_base.Key_binding_info.make_grid_lookup grid_contents

    let main ~input_mode =
      Ui_base.Key_binding_info.main ~grid_lookup ~input_mode
  end

  let search_bar ~input_mode =
    Ui_base.Search_bar.main ~input_mode
      ~edit_field:Vars.search_field
      ~focus_handle:Vars.search_field_focus_handle
      ~f:update_search_phrase

  let main ~document_info_s =
    let$* input_mode = Lwd.get Ui_base.Vars.input_mode in
    Nottui_widgets.vbox
      [
        status_bar ~document_info_s ~input_mode;
        Key_binding_info.main ~input_mode;
        search_bar ~input_mode;
      ]
end

let keyboard_handler
    ~(document_info_s : Document_store.value array)
    (key : Nottui.Ui.key)
  =
  let document_choice_count =
    Array.length document_info_s
  in
  let document_current_choice =
    Lwd.peek Vars.index_of_document_selected
  in
  let document_info =
    if document_choice_count = 0 then
      None
    else
      Some document_info_s.(document_current_choice)
  in
  let search_result_choice_count =
    match document_info with
    | None -> 0
    | Some (_doc, search_results) -> Array.length search_results
  in
  let search_result_current_choice =
    Lwd.peek Vars.index_of_search_result_selected
  in
  match Lwd.peek Ui_base.Vars.input_mode with
  | Navigate -> (
      match key with
      | (`Escape, [])
      | (`ASCII 'q', [])
      | (`ASCII 'C', [`Ctrl]) -> (
          Ui_base.Vars.file_to_open := None;
          Lwd.set Ui_base.Vars.quit true;
          `Handled
        )
      | (`ASCII 'r', []) -> (
          reload_document_selected ~document_info_s;
          `Handled
        )
      | (`Tab, []) -> (
          Option.iter (fun (doc, _search_results) ->
              let document_store = Lwd.peek Ui_base.Vars.document_store in
              let single_file_document_store =
                Option.get (Document_store.single_out ~path:doc.Document.path document_store)
              in
              Lwd.set Ui_base.Vars.Single_file.document_store single_file_document_store;
              Lwd.set Ui_base.Vars.Single_file.index_of_search_result_selected
                (Lwd.peek Vars.index_of_search_result_selected);
              Lwd.set Ui_base.Vars.Single_file.search_field
                (Lwd.peek Vars.search_field);
              Lwd.set Ui_base.Vars.ui_mode Ui_single_file;
            )
            document_info;
          `Handled
        )
      | (`Page `Down, [`Shift])
      | (`ASCII 'J', [])
      | (`Arrow `Down, [`Shift]) -> (
          set_search_result_selected
            ~choice_count:search_result_choice_count
            (search_result_current_choice+1);
          `Handled
        )
      | (`Page `Up, [`Shift])
      | (`ASCII 'K', [])
      | (`Arrow `Up, [`Shift]) -> (
          set_search_result_selected
            ~choice_count:search_result_choice_count
            (search_result_current_choice-1);
          `Handled
        )
      | (`Page `Down, [])
      | (`ASCII 'j', [])
      | (`Arrow `Down, []) -> (
          set_document_selected
            ~choice_count:document_choice_count
            (document_current_choice+1);
          `Handled
        )
      | (`Page `Up, [])
      | (`ASCII 'k', [])
      | (`Arrow `Up, []) -> (
          set_document_selected
            ~choice_count:document_choice_count
            (document_current_choice-1);
          `Handled
        )
      | (`ASCII '/', []) -> (
          Nottui.Focus.request Vars.search_field_focus_handle;
          Lwd.set Ui_base.Vars.input_mode Search;
          `Handled
        )
      | (`ASCII 'x', []) -> (
          Lwd.set Vars.search_field Ui_base.empty_search_field;
          update_search_phrase ();
          `Handled
        )
      | (`Enter, []) -> (
          Option.iter (fun (doc, _search_results) ->
              match doc.Document.path with
              | Some path when Misc_utils.path_is_pdf path -> ()
              | _ -> (
                  Ui_base.Vars.file_to_open := Some doc;
                  Lwd.set Ui_base.Vars.quit true;
                )
            )
            document_info;
          `Handled
        )
      | _ -> `Handled
    )
  | Search -> `Unhandled

let main : Nottui.ui Lwd.t =
  let$* document_store = Lwd.get Ui_base.Vars.document_store in
  let document_info_s =
    Document_store.usable_documents document_store
  in
  Nottui_widgets.vbox
    [
      (let$ top_pane = Top_pane.main ~document_info_s in
       Nottui.Ui.keyboard_area
         (keyboard_handler ~document_info_s)
         top_pane);
      Bottom_pane.main ~document_info_s;
    ]