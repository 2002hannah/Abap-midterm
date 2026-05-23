*&---------------------------------------------------------------------*
*& Report Z_THREE_LAYER_ALV_SALES
*&---------------------------------------------------------------------*
*& 商業情境：銷售訂單(Header) -> 訂單明細(Item) -> 庫存與顏色預警(Stock)
*& 終極技術：加入全域旗標防止 Container 重複初始化快取衝突
*&---------------------------------------------------------------------*
REPORT z_three_layer_alv_sales.

"----------------------------------------------------------------------"
" 1. 資料結構定義
"----------------------------------------------------------------------"
TYPES: BEGIN OF ty_vbak,
         vbeln TYPE vbak-vbeln, " 銷售單號
         erdat TYPE vbak-erdat, " 建立日期
         kunnr TYPE vbak-kunnr, " 客戶編號
         netwr TYPE vbak-netwr, " 總金額
         waerk TYPE vbak-waerk, " 幣別
       END OF ty_vbak.

TYPES: BEGIN OF ty_vbap,
         vbeln TYPE vbap-vbeln, " 銷售單號
         posnr TYPE vbap-posnr, " 項目號碼
         matnr TYPE vbap-matnr, " 物料編號
         kwmeng TYPE vbap-kwmeng, " 訂單數量
         vrkme TYPE vbap-vrkme, " 單位
       END OF ty_vbap.

TYPES: BEGIN OF ty_mard,
         matnr TYPE mard-matnr, " 物料編號
         werks TYPE mard-werks, " 工廠
         lgort TYPE mard-lgort, " 儲位
         labst TYPE mard-labst, " 庫存數量
         t_color TYPE lvc_t_scol, " 用於動態儲存格顏色
       END OF ty_mard.

DATA: gt_vbak TYPE TABLE OF ty_vbak,
      gt_vbap TYPE TABLE OF ty_vbap,
      gt_mard TYPE TABLE OF ty_mard,
      gs_vbak TYPE ty_vbak.

" ALV 控制物件
DATA: go_docking    TYPE REF TO cl_gui_docking_container,
      go_splitter   TYPE REF TO cl_gui_splitter_container,
      go_cell_top   TYPE REF TO cl_gui_container,
      go_cell_mid   TYPE REF TO cl_gui_container,
      go_cell_bot   TYPE REF TO cl_gui_container,
      go_grid1      TYPE REF TO cl_gui_alv_grid,
      go_grid2      TYPE REF TO cl_gui_alv_grid,
      go_grid3      TYPE REF TO cl_gui_alv_grid.

" ALV 配置結構
DATA: gs_layout1 TYPE lvc_s_layo,
      gs_layout2 TYPE lvc_s_layo,
      gs_layout3 TYPE lvc_s_layo,
      gt_fcat1   TYPE lvc_t_fcat,
      gt_fcat2   TYPE lvc_t_fcat,
      gt_fcat3   TYPE lvc_t_fcat.

" 【防當機核心】宣告全域初次顯示旗標 (X = 已建立過首次顯示)
DATA: gv_alv2_initialized TYPE c,
      gv_alv3_initialized TYPE c.

" 選擇畫面
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS: s_vbeln FOR gs_vbak-vbeln,
                  s_erdat FOR gs_vbak-erdat.
SELECTION-SCREEN END OF BLOCK b1.

"----------------------------------------------------------------------"
" 2. 事件處理類別定義
"----------------------------------------------------------------------"
CLASS lcl_event_handler DEFINITION.
  PUBLIC SECTION.
    METHODS handle_double_click1
      FOR EVENT double_click OF cl_gui_alv_grid
      IMPORTING e_row e_column.

    METHODS handle_double_click2
      FOR EVENT double_click OF cl_gui_alv_grid
      IMPORTING e_row e_column.

    METHODS handle_toolbar1
      FOR EVENT toolbar OF cl_gui_alv_grid
      IMPORTING e_object e_interactive.

    METHODS handle_user_command1
      FOR EVENT user_command OF cl_gui_alv_grid
      IMPORTING e_ucomm.
ENDCLASS.

DATA: go_handler TYPE REF TO lcl_event_handler.

"----------------------------------------------------------------------"
" 3. 主要程式流程
"----------------------------------------------------------------------"
START-OF-SELECTION.
  PERFORM f_fetch_vbak_data.
  IF gt_vbak IS INITIAL.
    MESSAGE '在指定條件下查無銷售訂單資料！' TYPE 'I'.
    LEAVE TO LIST-PROCESSING.
  ELSE.
    CALL SCREEN 0100.
  ENDIF.

*&---------------------------------------------------------------------*
*& Module STATUS_0100 OUTPUT (螢幕 PBO)
*&---------------------------------------------------------------------*
MODULE status_0100 OUTPUT.
  SET PF-STATUS 'STATUS_0100'.
  SET TITLEBAR 'TITLE_0100'.

  IF go_docking IS INITIAL.
    PERFORM f_init_containers.
    PERFORM f_display_alv1.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0100 INPUT (螢幕 PAI)
*&---------------------------------------------------------------------*
MODULE user_command_0100 INPUT.
  CASE sy-ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL'.
      IF go_docking IS NOT INITIAL.
        go_docking->free( ).
      ENDIF.
      SET SCREEN 0. LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

"----------------------------------------------------------------------"
" 4. 子程序實作
"----------------------------------------------------------------------"
FORM f_fetch_vbak_data.
  SELECT vbeln erdat kunnr netwr waerk
    FROM vbak
    INTO TABLE gt_vbak
    WHERE vbeln IN s_vbeln
      AND erdat IN s_erdat.
ENDFORM.

FORM f_init_containers.
  CREATE OBJECT go_docking
    EXPORTING
      repid     = sy-repid
      dynnr     = '0100'
      side      = cl_gui_docking_container=>dock_at_left
      extension = 9999.

  CREATE OBJECT go_splitter
    EXPORTING
      parent  = go_docking
      rows    = 3
      columns = 1.

  go_splitter->set_row_height( id = 1 height = 30 ).
  go_splitter->set_row_height( id = 2 height = 35 ).
  go_splitter->set_row_height( id = 3 height = 35 ).

  go_cell_top = go_splitter->get_container( row = 1 column = 1 ).
  go_cell_mid = go_splitter->get_container( row = 2 column = 1 ).
  go_cell_bot = go_splitter->get_container( row = 3 column = 1 ).

  CREATE OBJECT go_grid1 EXPORTING i_parent = go_cell_top.
  CREATE OBJECT go_grid2 EXPORTING i_parent = go_cell_mid.
  CREATE OBJECT go_grid3 EXPORTING i_parent = go_cell_bot.

  CREATE OBJECT go_handler.
  SET HANDLER go_handler->handle_double_click1 FOR go_grid1.
  SET HANDLER go_handler->handle_double_click2 FOR go_grid2.
  SET HANDLER go_handler->handle_toolbar1      FOR go_grid1.
  SET HANDLER go_handler->handle_user_command1 FOR go_grid1.
ENDFORM.

FORM f_display_alv1.
  DATA: ls_fcat TYPE lvc_s_fcat.
  REFRESH gt_fcat1.

  CLEAR ls_fcat. ls_fcat-fieldname = 'VBELN'. ls_fcat-scrtext_m = '銷售單號'. APPEND ls_fcat TO gt_fcat1.
  CLEAR ls_fcat. ls_fcat-fieldname = 'ERDAT'. ls_fcat-scrtext_m = '建立日期'. APPEND ls_fcat TO gt_fcat1.
  CLEAR ls_fcat. ls_fcat-fieldname = 'KUNNR'. ls_fcat-scrtext_m = '客戶編號'. APPEND ls_fcat TO gt_fcat1.
  CLEAR ls_fcat. ls_fcat-fieldname = 'NETWR'. ls_fcat-scrtext_m = '總金額'.   APPEND ls_fcat TO gt_fcat1.
  CLEAR ls_fcat. ls_fcat-fieldname = 'WAERK'. ls_fcat-scrtext_m = '幣別'.     APPEND ls_fcat TO gt_fcat1.

  CLEAR gs_layout1.
  gs_layout1-zebra      = 'X'.
  gs_layout1-cwidth_opt = 'X'.
  gs_layout1-grid_title = '第一層：銷售訂單主檔 (雙擊單號查詢明細)'.

  go_grid1->set_table_for_first_display(
    EXPORTING is_layout = gs_layout1
    CHANGING it_outtab = gt_vbak
             it_fieldcatalog = gt_fcat1 ).
ENDFORM.

"----------------------------------------------------------------------"
" 5. 事件處理類別實作
"----------------------------------------------------------------------"
CLASS lcl_event_handler IMPLEMENTATION.

  "--- 第一層雙擊：更新第二層明細 ---"
  METHOD handle_double_click1.
    DATA: ls_vbak TYPE ty_vbak,
          ls_fcat TYPE lvc_s_fcat,
          ls_stbl TYPE lvc_s_stbl.

    READ TABLE gt_vbak INTO ls_vbak INDEX e_row-index.
    IF sy-subrc = 0.
      SELECT vbeln posnr matnr kwmeng vrkme
        FROM vbap
        INTO TABLE gt_vbap
        WHERE vbeln = ls_vbak-vbeln.

      IF gt_vbap IS INITIAL.
        MESSAGE '該訂單無明細項目資料' TYPE 'S' DISPLAY LIKE 'W'.
      ENDIF.

      " 快取安全機制：如果是第一次點擊，才建立欄位與初始化
      IF gv_alv2_initialized IS INITIAL.
        REFRESH gt_fcat2.
        CLEAR ls_fcat. ls_fcat-fieldname = 'VBELN'.  ls_fcat-scrtext_m = '銷售單號'. APPEND ls_fcat TO gt_fcat2.
        CLEAR ls_fcat. ls_fcat-fieldname = 'POSNR'.  ls_fcat-scrtext_m = '項目號碼'. APPEND ls_fcat TO gt_fcat2.
        CLEAR ls_fcat. ls_fcat-fieldname = 'MATNR'.  ls_fcat-scrtext_m = '物料編號'. APPEND ls_fcat TO gt_fcat2.
        CLEAR ls_fcat. ls_fcat-fieldname = 'KWMENG'. ls_fcat-scrtext_m = '訂單數量'. APPEND ls_fcat TO gt_fcat2.
        CLEAR ls_fcat. ls_fcat-fieldname = 'VRKME'.  ls_fcat-scrtext_m = '單位'.     APPEND ls_fcat TO gt_fcat2.

        CLEAR gs_layout2.
        gs_layout2-zebra      = 'X'.
        gs_layout2-cwidth_opt = 'X'.
        gs_layout2-grid_title = '第二層：訂單明細項目'.

        go_grid2->set_table_for_first_display(
          EXPORTING is_layout = gs_layout2
          CHANGING it_outtab = gt_vbap
                   it_fieldcatalog = gt_fcat2 ).

        gv_alv2_initialized = 'X'. " 打開旗標，以後不再跑首次顯示
      ELSE.
        " 後續切換資料，直接用 Refresh，穩定不崩潰！
        ls_stbl-row = 'X'. ls_stbl-col = 'X'.
        go_grid2->refresh_table_display( is_stable = ls_stbl ).
      ENDIF.

      " 連動清空第三層，防止上一次物料的庫存遺留
      CLEAR gt_mard.
      IF gv_alv3_initialized = 'X'.
        ls_stbl-row = 'X'. ls_stbl-col = 'X'.
        go_grid3->refresh_table_display( is_stable = ls_stbl ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  "--- 第二層雙擊：更新第三層庫存（含警示色）---"
  METHOD handle_double_click2.
    DATA: ls_vbap  TYPE ty_vbap,
          ls_mard  TYPE ty_mard,
          ls_color TYPE lvc_s_scol,
          ls_fcat  TYPE lvc_s_fcat,
          ls_stbl  TYPE lvc_s_stbl.

    READ TABLE gt_vbap INTO ls_vbap INDEX e_row-index.
    IF sy-subrc = 0.
      SELECT matnr werks lgort labst
        FROM mard
        INTO CORRESPONDING FIELDS OF TABLE gt_mard
        WHERE matnr = ls_vbap-matnr.

      " 動態庫存預警顏色配置
      LOOP AT gt_mard INTO ls_mard.
        CLEAR ls_mard-t_color.
        IF ls_mard-labst <= 50.
          ls_color-fname = ''.
          ls_color-color-col = 6. " 高亮紅
          ls_color-color-int = 1.
          INSERT ls_color INTO TABLE ls_mard-t_color.
          MODIFY gt_mard FROM ls_mard TRANSPORTING t_color.
        ENDIF.
      ENDLOOP.

      " 快取安全機制：第三層的首次與二次更新調控
      IF gv_alv3_initialized IS INITIAL.
        REFRESH gt_fcat3.
        CLEAR ls_fcat. ls_fcat-fieldname = 'MATNR'. ls_fcat-scrtext_m = '物料編號'. APPEND ls_fcat TO gt_fcat3.
        CLEAR ls_fcat. ls_fcat-fieldname = 'WERKS'. ls_fcat-scrtext_m = '工廠'.     APPEND ls_fcat TO gt_fcat3.
        CLEAR ls_fcat. ls_fcat-fieldname = 'LGORT'. ls_fcat-scrtext_m = '儲位'.     APPEND ls_fcat TO gt_fcat3.
        CLEAR ls_fcat. ls_fcat-fieldname = 'LABST'. ls_fcat-scrtext_m = '庫存數量'. APPEND ls_fcat TO gt_fcat3.

        CLEAR gs_layout3.
        gs_layout3-ctab_fname = 'T_COLOR'.
        gs_layout3-zebra      = 'X'.
        gs_layout3-cwidth_opt = 'X'.
        gs_layout3-grid_title = '第三層：即時庫存預警 (紅色代表低於安全庫存)'.

        go_grid3->set_table_for_first_display(
          EXPORTING is_layout = gs_layout3
          CHANGING it_outtab = gt_mard
                   it_fieldcatalog = gt_fcat3 ).

        gv_alv3_initialized = 'X'. " 打開旗標
      ELSE.
        " 已經初始化過，直接安全刷新數據
        ls_stbl-row = 'X'. ls_stbl-col = 'X'.
        go_grid3->refresh_table_display( is_stable = ls_stbl ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  "--- 第一層工具列按鈕定義 ---"
  METHOD handle_toolbar1.
    DATA: ls_toolbar TYPE stb_button.
    CLEAR ls_toolbar. ls_toolbar-butn_type = 3. INSERT ls_toolbar INTO TABLE e_object->mt_toolbar.
    CLEAR ls_toolbar.
    ls_toolbar-function  = 'VA03_JUMP'.
    ls_toolbar-icon      = "@16@".
    ls_toolbar-quickinfo = '跳轉至 VA03 查看標準銷售單據'.
    ls_toolbar-text      = '開啟標準單據(VA03)'.
    INSERT ls_toolbar INTO TABLE e_object->mt_toolbar.
  ENDMETHOD.

  "--- 工具列按鈕功能實作 ---"
  METHOD handle_user_command1.
    DATA: lv_row   TYPE i,
          ls_vbak  TYPE ty_vbak.

    CASE e_ucomm.
      WHEN 'VA03_JUMP'.
        go_grid1->get_current_cell( IMPORTING e_row = lv_row ).
        READ TABLE gt_vbak INTO ls_vbak INDEX lv_row.
        IF sy-subrc = 0 AND ls_vbak-vbeln IS NOT INITIAL.
          SET PARAMETER ID 'AUN' FIELD ls_vbak-vbeln.
          CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN.
        ELSE.
          MESSAGE '請先選擇一筆銷售訂單列！' TYPE 'I'.
        ENDIF.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.
