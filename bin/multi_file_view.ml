open Docfd_lib
open Lwd_infix

module Vars = struct
  let index_of_document_selected = Lwd.var 0

  let index_of_search_result_selected = Lwd.var 0

  let search_field = Lwd.var Ui_base.empty_text_field

  let search_field_focus_handle = Nottui.Focus.make ()

  let require_field = Lwd.var Ui_base.empty_text_field

  let require_field_focus_handle = Nottui.Focus.make ()
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
  let pool = Ui_base.task_pool () in
  match
    Document.of_path ~env:(Ui_base.eio_env ()) pool (Document.search_mode doc) (Document.path doc)
  with
  | Ok doc -> (
      reset_document_selected ();
      let document_store =
        Lwd.peek Ui_base.Vars.document_store
        |> Document_store.add_document pool doc
      in
      Lwd.set Ui_base.Vars.document_store document_store;
    )
  | Error _ -> ()

let reload_document_selected
    ~(document_info_s : Document_store.document_info array)
  : unit =
  if Array.length document_info_s > 0 then (
    let index = Lwd.peek Vars.index_of_document_selected in
    let doc, _search_results = document_info_s.(index) in
    reload_document doc;
  )

let update_search_phrase () =
  reset_document_selected ();
  let s = fst @@ Lwd.peek Vars.search_field in
  Search_manager.submit_search_req s Ui_base.Vars.document_store

module Top_pane = struct
  module Document_list = struct
    let render_document_preview
        ~width
        ~(document_info : Document_store.document_info)
        ~selected
      : Notty.image =
      let open Notty in
      let open Notty.Infix in
      let (doc, search_results) = document_info in
      let search_result_score_image =
        if Option.is_some !Params.debug_output then (
          if Array.length search_results = 0 then
            I.empty
          else (
            let x = search_results.(0) in
            I.strf "(Best search result score: %f)" (Search_result.score x)
          )
        ) else (
          I.empty
        )
      in
      let sub_item_base_left_padding = I.string A.empty "    " in
      let sub_item_width = width - I.width sub_item_base_left_padding - 2 in
      let preview_left_padding_per_line =
        I.string A.(bg lightgreen) " "
        <|>
        I.string A.empty " "
      in
      let preview_line_images =
        let line_count =
          min Params.preview_line_count (Index.global_line_count (Document.index doc))
        in
        OSeq.(0 --^ line_count)
        |> Seq.map (fun global_line_num ->
            Index.words_of_global_line_num global_line_num (Document.index doc)
            |> List.of_seq
            |> Content_and_search_result_render.Text_block_render.of_words ~width:sub_item_width
          )
        |> Seq.map (fun img ->
            let left_padding =
              OSeq.(0 --^ I.height img)
              |> Seq.map (fun _ -> preview_left_padding_per_line)
              |> List.of_seq
              |> I.vcat
            in
            left_padding <|> img
          )
        |> List.of_seq
      in
      let preview_image =
        I.vcat preview_line_images
      in
      let path_image =
        (I.string A.(fg lightgreen) "@ ")
        <|>
        (Document.path doc
         |> File_utils.remove_cwd_from_path
         |> Tokenize.tokenize ~drop_spaces:false
         |> List.of_seq
         |> Content_and_search_result_render.Text_block_render.of_words ~width:sub_item_width
        )
      in
      let last_scan_image =
        I.string A.(fg lightgreen) "Last scan: "
        <|>
        I.string A.empty
          (Timedesc.to_string ~format:Params.last_scan_format_string (Document.last_scan doc))
      in
      let title =
        let attr =
          if selected then (
            A.(fg lightblue ++ st bold)
          ) else (
            A.(fg lightblue)
          )
        in
        Option.value ~default:"" (Document.title doc)
        |> Tokenize.tokenize ~drop_spaces:false
        |> List.of_seq
        |> Content_and_search_result_render.Text_block_render.of_words ~attr ~width
      in
      title
      <->
      (sub_item_base_left_padding
       <|>
       I.vcat
         [ search_result_score_image;
           path_image;
           preview_image;
           last_scan_image;
         ]
      )

    let main
        ~width
        ~height
        ~(document_info_s : Document_store.document_info array)
        ~(document_selected : int)
      : Nottui.ui Lwd.t =
      let document_count = Array.length document_info_s in
      let render_pane () =
        let rec aux index height_filled acc =
          if index < document_count
          && height_filled < height
          then (
            let selected = Int.equal document_selected index in
            let img = render_document_preview ~width ~document_info:document_info_s.(index) ~selected in
            aux (index + 1) (height_filled + Notty.I.height img) (img :: acc)
          ) else (
            List.rev acc
            |> List.map Nottui.Ui.atom
            |> Nottui.Ui.vcat
          )
        in
        if document_count = 0 then (
          Nottui.Ui.empty
        ) else (
          aux document_selected 0 []
        )
      in
      let$ background = Ui_base.full_term_sized_background in
      Nottui.Ui.join_z background (render_pane ())
      |> Nottui.Ui.mouse_area
        (Ui_base.mouse_handler
           ~f:(fun direction ->
               let offset =
                 match direction with
                 | `Up -> -1
                 | `Down -> 1
               in
               let document_current_choice =
                 Lwd.peek Vars.index_of_document_selected
               in
               set_document_selected
                 ~choice_count:document_count
                 (document_current_choice + offset);
             )
        )
  end

  module Right_pane = struct
    let main
        ~width
        ~height
        ~(document_info_s : Document_store.document_info array)
        ~(document_selected : int)
      : Nottui.ui Lwd.t =
      if Array.length document_info_s = 0 then
        Nottui_widgets.(v_pane empty_lwd empty_lwd)
      else (
        let$* search_result_selected = Lwd.get Vars.index_of_search_result_selected in
        let document_info = document_info_s.(document_selected) in
        let sub_pane_height =
          height / 2
        in
        Nottui_widgets.v_pane
          (Ui_base.Content_view.main
             ~width
             ~height:sub_pane_height
             ~document_info
             ~search_result_selected)
          (Ui_base.Search_result_list.main
             ~width
             ~height:sub_pane_height
             ~document_info
             ~index_of_search_result_selected:Vars.index_of_search_result_selected)
      )
  end

  let main
      ~width
      ~height
      ~(document_info_s : Document_store.document_info array)
    : Nottui.ui Lwd.t =
    let$* document_selected = Lwd.get Vars.index_of_document_selected in
    let sub_pane_width =
      (* Minus 1 for pane separator bar. *)
      width / 2 - 1 - Params.line_wrap_underestimate_offset
    in
    Nottui_widgets.h_pane
      (Document_list.main
         ~width:sub_pane_width
         ~height
         ~document_info_s
         ~document_selected)
      (Right_pane.main
         ~width:sub_pane_width
         ~height
         ~document_info_s
         ~document_selected)
end

module Bottom_pane = struct
  let status_bar
      ~(document_info_s : Document_store.document_info array)
      ~(input_mode : Ui_base.input_mode)
    : Nottui.Ui.t Lwd.t =
    let$* index_of_document_selected = Lwd.get Vars.index_of_document_selected in
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
            document_count (Document_store.size (Lwd.peek Ui_base.Vars.document_store))
        in
        let index_of_selected =
          Notty.I.strf ~attr:Ui_base.Status_bar.attr
            "Index of document selected: %d"
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
    let$ bar = Ui_base.Status_bar.background_bar in
    Nottui.Ui.join_z bar content

  module Key_binding_info = struct
    let grid_contents : Ui_base.Key_binding_info.grid_contents =
      let open Ui_base.Key_binding_info in
      let empty_row =
        [
          { label = ""; msg = "" };
        ]
      in
      let navigate_grid =
        [
          [
            { label = "Enter"; msg = "open document" };
            { label = "/"; msg = "search mode" };
            { label = "x"; msg = "clear search" };
          ];
          [
            { label = "Tab"; msg = "single file view" };
            { label = "p"; msg = "print search result" };
            { label = "Shift+P"; msg = "print document path" };
          ];
          [
            { label = "r"; msg = "reload document selected" };
            { label = "Shift+R"; msg = "rescan for documents" };
          ];
        ]
      in
      let search_grid =
        [
          [
            { label = "Enter"; msg = "exit search mode" };
          ];
          empty_row;
          empty_row;
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
    ~(document_info_s : Document_store.document_info array)
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
      | (`ASCII 'Q', [`Ctrl])
      | (`ASCII 'C', [`Ctrl]) -> (
          Lwd.set Ui_base.Vars.quit true;
          Ui_base.Vars.action := None;
          `Handled
        )
      | (`ASCII 'R', []) -> (
          Ui_base.Key_binding_info.blink "Shift+R";
          reset_document_selected ();
          Lwd.set Ui_base.Vars.quit true;
          Ui_base.Vars.action := Some Ui_base.Recompute_document_src;
          `Handled
        )
      | (`ASCII 'r', []) -> (
          Ui_base.Key_binding_info.blink "r";
          reload_document_selected ~document_info_s;
          `Handled
        )
      | (`Tab, []) -> (
          Option.iter (fun (doc, _search_results) ->
              let document_store = Lwd.peek Ui_base.Vars.document_store in
              let single_file_document_store =
                Option.get (Document_store.single_out ~path:(Document.path doc) document_store)
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
          Ui_base.Key_binding_info.blink "x";
          Lwd.set Vars.search_field Ui_base.empty_text_field;
          update_search_phrase ();
          `Handled
        )
      | (`ASCII 'P', []) -> (
          Ui_base.Key_binding_info.blink "Shift+P";
          Option.iter (fun (doc, _search_results) ->
              Printers.Worker.submit_search_results_print_req `Stderr doc Seq.empty;
            )
            document_info;
          `Handled
        )
      | (`ASCII 'p', []) -> (
          Ui_base.Key_binding_info.blink "p";
          Option.iter (fun (doc, search_results) ->
              let search_results =
                if search_result_current_choice < Array.length search_results then
                  Seq.return search_results.(search_result_current_choice)
                else
                  Seq.empty
              in
              Printers.Worker.submit_search_results_print_req `Stderr doc search_results;
            )
            document_info;
          `Handled
        )
      | (`Enter, []) -> (
          Option.iter (fun (doc, search_results) ->
              let search_result =
                if search_result_current_choice < Array.length search_results then
                  Some search_results.(search_result_current_choice)
                else
                  None
              in
              Lwd.set Ui_base.Vars.quit true;
              Ui_base.Vars.action :=
                Some (Ui_base.Open_file_and_search_result (doc, search_result));
            )
            document_info;
          `Handled
        )
      | _ -> `Handled
    )
  | _ -> `Unhandled

let main : Nottui.ui Lwd.t =
  let$* document_store = Lwd.get Ui_base.Vars.document_store in
  let document_info_s =
    Document_store.usable_documents document_store
  in
  let$* bottom_pane = Bottom_pane.main ~document_info_s in
  let bottom_pane_height = Nottui.Ui.layout_height bottom_pane in
  let$* (term_width, term_height) = Lwd.get Ui_base.Vars.term_width_height in
  let top_pane_height = term_height - bottom_pane_height in
  let$* top_pane =
    Top_pane.main
      ~width:term_width
      ~height:top_pane_height
      ~document_info_s
  in
  Nottui_widgets.vbox
    [
      Lwd.return (Nottui.Ui.keyboard_area
                    (keyboard_handler ~document_info_s)
                    top_pane);
      Lwd.return bottom_pane;
    ]
