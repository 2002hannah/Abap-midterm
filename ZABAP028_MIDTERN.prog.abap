*&---------------------------------------------------------------------*
*& Report ZABAP028_MIDTERM
*&---------------------------------------------------------------------*
REPORT zabap028_midterm NO STANDARD PAGE HEADING LINE-SIZE 150.

" 簡短說明：
" - 支援三層視圖：Level1(訂單總覽)、Level2(訂單明細)、部門彙總 Dashboard。
" - 使用 HOTSPOT/HIDE 技術在 AT LINE-SELECTION 中識別使用者點擊的邏輯鍵。


TYPE-POOLS: icon.
TABLES: aufk.

TYPES: ty_aufnr_range TYPE RANGE OF aufk-aufnr.

" GLOBAL UI HELPERS
" gv_hide_* 用於 HOTSPOT/HIDE 模式：寫入 HOTSPOT 字段後立刻賦值並 HIDE，
" 以便在 AT LINE-SELECTION 中識別被點擊的業務鍵（例如訂單編號、科目等）。
DATA: gv_hide_aufnr      TYPE aufk-aufnr, " Level1 -> Level2 用的訂單熱點
  gv_hide_kstar      TYPE coep-kstar, " Level2 -> KA03 用的科目熱點
  gv_hide_summ_aufnr TYPE aufk-aufnr. " 部門彙總按鈕的熱點鍵

CONSTANTS:
  " 0100 放部門抬頭與操作，0200 放部門彙總清單
  c_screen_budget  TYPE sy-dynnr VALUE '0100',
  c_screen_history TYPE sy-dynnr VALUE '0200'.

DATA:
  gv_dialog_aufnr     TYPE aufk-aufnr,
  gv_dialog_kostl     TYPE aufk-kostv,
  gv_dialog_dept_name TYPE cskt-ktext,
  gv_dialog_okcode    TYPE sy-ucomm,
  gv_show_summary     TYPE abap_bool.

*----------------------------------------------------------------------*
* 類別定義：lcl_report
* - 負責資料抓取、計算指標、與列印三層報表視圖
* - 保持 UI 與邏輯分離，所有列印都集中在 display_* 方法
*----------------------------------------------------------------------*
CLASS lcl_report DEFINITION.
  PUBLIC SECTION.

    "=== Level 1 / Level 2 結構 ===
    TYPES: BEGIN OF ty_level1,
             light    TYPE icon_d,                 " 狀態燈號
             aufnr    TYPE aufk-aufnr,             " 內部訂單號碼
             ktext    TYPE aufk-ktext,             " 訂單描述
             plan_amt TYPE p LENGTH 10 DECIMALS 2, " 預算金額(USD)
             act_amt  TYPE p LENGTH 10 DECIMALS 2, " 實際支出(USD)
             usage    TYPE p LENGTH 6 DECIMALS 2,  " 執行率(%)
           END OF ty_level1,

           BEGIN OF ty_level2,
             kstar  TYPE coep-kstar, " 成本要素
             txt20  TYPE skat-txt20, " 科目名稱
             wtgbtr TYPE coep-wtgbtr, " 實際金額(USD)
             perio  TYPE coep-perio, " 會計期間
             belnr  TYPE coep-belnr, " 傳票號碼
           END OF ty_level2,

           "=== 部門彙總 結構 ===
           BEGIN OF ty_department_order,
             light    TYPE icon_d,                 " 狀態燈號
             aufnr    TYPE aufk-aufnr,             " 內部訂單號碼
             ktext    TYPE aufk-ktext,             " 訂單描述
             kostv    TYPE aufk-kostv,             " 成本中心
             plan_amt TYPE p LENGTH 10 DECIMALS 2, " 預算金額(USD)
             act_amt  TYPE p LENGTH 10 DECIMALS 2, " 實際支出(USD)
             usage    TYPE p LENGTH 6 DECIMALS 2,  " 執行率(%)
           END OF ty_department_order.

    "=== 內表宣告 ===
    DATA: mt_level1           TYPE TABLE OF ty_level1,
          mt_level2           TYPE TABLE OF ty_level2,
          mt_department_orders TYPE TABLE OF ty_department_order.

    "=== Methods ===
    METHODS:
      get_data_l1 IMPORTING it_aufnr TYPE ty_aufnr_range iv_kokrs TYPE aufk-kokrs,
      display_l1,
      get_data_l2 IMPORTING iv_aufnr TYPE aufk-aufnr,
      display_l2  IMPORTING iv_aufnr TYPE aufk-aufnr,
      jump_ka03   IMPORTING iv_kstar TYPE coep-kstar iv_kokrs TYPE aufk-kokrs,
      open_department_dialog IMPORTING iv_aufnr TYPE aufk-aufnr,
      get_department_name    IMPORTING iv_kostv TYPE aufk-kostv,
      display_department_orders IMPORTING iv_kostv TYPE aufk-kostv iv_kokrs TYPE aufk-kokrs.

  PRIVATE SECTION.
    METHODS sanitize_text
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.

*----------------------------------------------------------------------*
* 類別實作 (核心對齊邏輯)
*----------------------------------------------------------------------*
CLASS lcl_report IMPLEMENTATION.
  "------------------------------------------------------------------
  " METHOD: sanitize_text
  " 說明: 以安全方式移除文字中的換行（CR/LF）、newline、tab，
  "       並壓縮空白，回傳一個不含控制字元的檔案友善字串。
  " 參數: iv_text TYPE csequence - 原始文字
  " 回傳: rv_text TYPE string    - 處理後的文字
  " 影響: 用於顯示欄位前，避免換行破壞固定寬度表格
  "------------------------------------------------------------------
  METHOD sanitize_text.
    " 功能：移除文字中的換行與製表符，並壓縮空白，避免破壞固定欄位排版
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH space.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH space.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_text WITH space.
    CONDENSE rv_text.
  ENDMETHOD.

  "------------------------------------------------------------------
  " METHOD: get_data_l1
  " 說明: 讀取 Level1 內部訂單清單 (aufk)，計算每筆的實際支出、
  "       預算及執行率，並根據執行率設定燈號狀態。
  " 參數: it_aufnr TYPE ty_aufnr_range - 查詢訂單範圍
  "       iv_kokrs TYPE aufk-kokrs     - 公司代碼
  " 回傳: 無 (填充 internal table mt_level1)
  "------------------------------------------------------------------
  METHOD get_data_l1.
    " 功能：讀取 Level1 訂單清單，並計算預算/實際/執行率與燈號
    CLEAR mt_level1.
    SELECT aufnr, ktext
      FROM aufk
      INTO CORRESPONDING FIELDS OF TABLE @mt_level1
      WHERE aufnr IN @it_aufnr
        AND kokrs = @iv_kokrs.

    LOOP AT mt_level1 ASSIGNING FIELD-SYMBOL(<ls_l1>).
      SELECT SUM( wtgbtr )
        FROM coep
        INTO @<ls_l1>-act_amt
        WHERE aufnr = @<ls_l1>-aufnr.

      <ls_l1>-plan_amt = 2500.

      IF <ls_l1>-plan_amt <> 0.
        <ls_l1>-usage = ( <ls_l1>-act_amt / <ls_l1>-plan_amt ) * 100.
      ENDIF.

      IF <ls_l1>-usage >= 100.
        <ls_l1>-light = icon_red_light.
      ELSEIF <ls_l1>-usage >= 80.
        <ls_l1>-light = icon_yellow_light.
      ELSE.
        <ls_l1>-light = icon_green_light.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " AT LINE-SELECTION handler: 在檔案末段有 AT LINE-SELECTION 使用 gv_hide_* 判斷

  "------------------------------------------------------------------
  " METHOD: display_l1
  " 說明: 列印 Level1 總覽卡與訂單列表，使用固定欄位排版並套用
  "       HOTSPOT/HIDE 模式使列表可互動（點訂單跳明細、點 >> 開部門）。
  " 參數: 無（使用 mt_level1 之資料）
  " 回傳: 無（直接寫出至列表畫面）
  "------------------------------------------------------------------
  METHOD display_l1.
    " 功能：列印 Level1 總覽卡與訂單列表（固定欄位格式）
    DATA: lv_cnt_red    TYPE i,
          lv_cnt_yellow TYPE i,
          lv_cnt_green  TYPE i,
          lv_ktext_disp TYPE string,
          lv_order_cnt  TYPE i.

    " 每次列印前清除 HOTSPOT 快取變數，避免誤判使用者點擊
    CLEAR: gv_hide_aufnr, gv_hide_summ_aufnr.

    LOOP AT mt_level1 INTO DATA(ls_stat).
      CASE ls_stat-light.
        WHEN icon_red_light.
          lv_cnt_red = lv_cnt_red + 1.
        WHEN icon_yellow_light.
          lv_cnt_yellow = lv_cnt_yellow + 1.
        WHEN icon_green_light.
          lv_cnt_green = lv_cnt_green + 1.
      ENDCASE.
    ENDLOOP.
    lv_order_cnt = lines( mt_level1 ).

    SKIP.
    ULINE /1(50).
    FORMAT COLOR COL_HEADING INTENSIFIED ON.
    WRITE: / '|', (48) '內部訂單總覽' CENTERED, '|'.
    FORMAT COLOR OFF.

    ULINE /1(50).
    FORMAT COLOR COL_HEADING.
    WRITE: / '|', (20) '項目', '|', (26) '數值', '|'.
    FORMAT COLOR OFF.

    ULINE /1(50).
    WRITE: / '|', (20) '訂單數', '|', (26) lv_order_cnt, '|'.

    ULINE /1(50).
    WRITE: / '|', (20) '紅燈數' COLOR COL_NEGATIVE, '|', (26) lv_cnt_red COLOR COL_NEGATIVE, '|'.

    ULINE /1(50).
    WRITE: / '|', (20) '黃燈數' COLOR COL_TOTAL, '|', (26) lv_cnt_yellow COLOR COL_TOTAL, '|'.

    ULINE /1(50).
    WRITE: / '|', (20) '綠燈數' COLOR COL_POSITIVE, '|', (26) lv_cnt_green COLOR COL_POSITIVE, '|'.

    ULINE /1(50). " ➔ 補上最底部的關閉線


        ULINE AT (108).
        FORMAT COLOR COL_HEADING.
        WRITE: / '|', (4) '狀態', '|', (12) '內部訂單', '|', (34) '描述',
          '|', (14) '預算(USD)', '|', (14) '實際(USD)', '|', (8) '執行率%',
          '|', (14) '部門彙總', '|'.
        FORMAT COLOR OFF.
        ULINE AT (108).

    LOOP AT mt_level1 INTO DATA(ls_l1).
      WRITE: / '|', (4) ls_l1-light AS ICON.

      " === 核心修正點 2：內部訂單 Hotspot，寫完立刻使用 HIDE 凍結當前行數值 ===
      gv_hide_aufnr = ls_l1-aufnr.
      WRITE: '|', (12) ls_l1-aufnr COLOR COL_KEY HOTSPOT ON.
      HIDE gv_hide_aufnr.

      lv_ktext_disp = me->sanitize_text( ls_l1-ktext ).
      WRITE: '|', (34) lv_ktext_disp.
      WRITE: '|', (14) ls_l1-plan_amt CURRENCY 'USD'.
      WRITE: '|', (14) ls_l1-act_amt CURRENCY 'USD'.
      WRITE: '|', (8) ls_l1-usage DECIMALS 2.

      " === 核心修正點 3：部門彙總獨立按鈕 Hotspot (箭頭)，寫完也立刻使用 HIDE 凍結 ===
      gv_hide_summ_aufnr = ls_l1-aufnr.
      WRITE: '|', (14) '>>' CENTERED COLOR COL_KEY HOTSPOT ON, '|'.
      HIDE gv_hide_summ_aufnr.

      ULINE AT (108).
    ENDLOOP.
  ENDMETHOD.

  "------------------------------------------------------------------
  " METHOD: get_data_l2
  " 說明: 讀取指定訂單 (iv_aufnr) 的成本要素明細 (coep)，
  "       並填充 mt_level2 以供 display_l2 顯示。
  " 參數: iv_aufnr TYPE aufk-aufnr - 目標訂單
  "------------------------------------------------------------------
  METHOD get_data_l2.
    " 功能：讀取 Level2 明細（按訂單），填充 mt_level2
    CLEAR mt_level2.
    SELECT c~kstar, s~txt20, c~wtgbtr, c~perio, c~belnr
      FROM coep AS c
      LEFT JOIN skat AS s ON c~kstar = s~saknr AND s~spras = @sy-langu
      INTO CORRESPONDING FIELDS OF TABLE @mt_level2
      WHERE c~aufnr = @iv_aufnr.
  ENDMETHOD.

  "------------------------------------------------------------------
  " METHOD: display_l2
  " 說明: 列印 Level2 明細表（成本要素、科目名稱、實際金額、期間、傳票）。
  "       每一科目欄位支援 HOTSPOT，可跳至 KA03。
  " 參數: iv_aufnr TYPE aufk-aufnr - 目前顯示之訂單（顯示標題用）
  "------------------------------------------------------------------
  METHOD display_l2.
    " 功能：列印 Level2 明細表（成本要素 / 傳票等）
    WRITE: / '【明細報表】 訂單：', iv_aufnr COLOR COL_POSITIVE.
    ULINE AT (74).
    FORMAT COLOR COL_HEADING.
    WRITE: / '|', (12) '成本要素', '|', (24) '科目名稱', '|', (14) '實際(USD)', '|', (6) '期間', '|', (12) '傳票號碼', '|'.
    FORMAT COLOR OFF.
    ULINE AT (74).

    LOOP AT mt_level2 INTO DATA(ls_l2).
      gv_hide_kstar = ls_l2-kstar.
      WRITE: / '|', (12) ls_l2-kstar COLOR COL_KEY HOTSPOT ON,
               '|', (24) ls_l2-txt20,
               '|', (14) ls_l2-wtgbtr CURRENCY 'USD',
               '|', (6) ls_l2-perio,
               '|', (12) ls_l2-belnr, '|'.
      HIDE gv_hide_kstar.
    ENDLOOP.
    ULINE AT (74).
  ENDMETHOD.

  "------------------------------------------------------------------
  " METHOD: jump_ka03
  " 說明: 設定必要的 PARAMETER ID，並執行 CALL TRANSACTION 'KA03'
  "       以檢視科目主檔。此為輔助快速導覽功能。
  " 參數: iv_kstar TYPE coep-kstar - 要查看的科目
  "       iv_kokrs TYPE aufk-kokrs - 公司代碼（傳參用）
  "------------------------------------------------------------------
  METHOD jump_ka03.
    " 功能：快速跳轉到 KA03 查看科目主檔
    SET PARAMETER ID 'KAS' FIELD iv_kstar.
    SET PARAMETER ID 'KOK' FIELD iv_kokrs.
    CALL TRANSACTION 'KA03' AND SKIP FIRST SCREEN.
  ENDMETHOD.

  "------------------------------------------------------------------
  " METHOD: get_department_name
  " 說明: 以成本中心編號查詢 cskt 取得成本中心名稱，若找不到
  "       則回傳預設顯示文字（'成本中心 <id>'）。
  " 參數: iv_kostv TYPE aufk-kostv - 成本中心編號
  " 回傳: 透過全域變數 gv_dialog_dept_name 設定名稱
  "------------------------------------------------------------------
  METHOD get_department_name.
    " 功能：查詢成本中心名稱，若找不到回傳預設顯示文字
    CLEAR gv_dialog_dept_name.
    SELECT SINGLE ktext
      FROM cskt
      INTO @gv_dialog_dept_name
      WHERE kostl = @iv_kostv
        AND spras = @sy-langu.
    IF sy-subrc <> 0.
      gv_dialog_dept_name = |成本中心 { iv_kostv }|.
    ENDIF.
  ENDMETHOD.

  "------------------------------------------------------------------
  " METHOD: open_department_dialog
  " 說明: 由傳入訂單 (iv_aufnr) 查出成本中心，若有找到則設定
  "       畫面所需的全域變數並執行 CALL SCREEN 進入部門檢視；
  "       若找不到則顯示資訊訊息並返回。
  " 參數: iv_aufnr TYPE aufk-aufnr - 來源訂單
  "------------------------------------------------------------------
  METHOD open_department_dialog.
    " 功能：開啟部門視圖，先查詢該訂單的成本中心，再 CALL SCREEN
    CLEAR: gv_dialog_okcode, gv_show_summary.
    gv_dialog_aufnr = iv_aufnr.

    SELECT SINGLE kostv
      FROM aufk
      INTO @gv_dialog_kostl
      WHERE aufnr = @iv_aufnr.

    IF sy-subrc = 0.
      me->get_department_name( iv_kostv = gv_dialog_kostl ).
    ELSE.
      CLEAR: gv_dialog_kostl, gv_dialog_dept_name.
      MESSAGE '找不到該內部訂單對應的成本中心，無法開啟部門畫面' TYPE 'I'.
      RETURN.
    ENDIF.

    CALL SCREEN c_screen_budget.
  ENDMETHOD.

      "------------------------------------------------------------------
      " METHOD: display_department_orders
      " 說明: 產生部門 Dashboard 與該部門所有訂單明細，計算 KPI（總預算、
      "       總實際、整體執行率）並將訂單依執行率排序顯示，畫面採固定
      "       欄位、色彩提示（紅/黃/綠燈）。
      " 參數: iv_kostv TYPE aufk-kostv - 成本中心
      "       iv_kokrs TYPE aufk-kokrs - 公司代碼
      "------------------------------------------------------------------
      METHOD display_department_orders.
        " 功能：產生部門彙總 Dashboard，包含 KPI 與該部門訂單明細
        DATA lv_act_amt TYPE p LENGTH 10 DECIMALS 2.
        DATA: lv_total_plan   TYPE p LENGTH 12 DECIMALS 2,
              lv_total_act    TYPE p LENGTH 12 DECIMALS 2,
              lv_total_usage  TYPE p LENGTH 7 DECIMALS 2,
              lv_count_red    TYPE i,
              lv_count_yellow TYPE i,
              lv_count_green  TYPE i,
              lv_variance     TYPE p LENGTH 12 DECIMALS 2,
              lv_ktext_disp   TYPE string,
              lv_order_cnt    TYPE i.
        CLEAR mt_department_orders.

        SELECT aufnr, ktext, kostv
          FROM aufk
          INTO CORRESPONDING FIELDS OF TABLE @mt_department_orders
          WHERE kostv = @iv_kostv
            AND kokrs = @iv_kokrs.

        LOOP AT mt_department_orders ASSIGNING FIELD-SYMBOL(<ls_order>).
          CLEAR lv_act_amt.
          SELECT SUM( wtgbtr ) FROM coep INTO @lv_act_amt WHERE aufnr = @<ls_order>-aufnr.
          <ls_order>-act_amt = lv_act_amt.
          <ls_order>-plan_amt = 2500.

          IF <ls_order>-plan_amt <> 0.
            <ls_order>-usage = ( <ls_order>-act_amt / <ls_order>-plan_amt ) * 100.
          ENDIF.

          IF <ls_order>-usage >= 100.
            <ls_order>-light = icon_red_light.
          ELSEIF <ls_order>-usage >= 80.
            <ls_order>-light = icon_yellow_light.
          ELSE.
            <ls_order>-light = icon_green_light.
          ENDIF.

          lv_total_plan = lv_total_plan + <ls_order>-plan_amt.
          lv_total_act  = lv_total_act + <ls_order>-act_amt.

          CASE <ls_order>-light.
            WHEN icon_red_light.
              lv_count_red = lv_count_red + 1.
            WHEN icon_yellow_light.
              lv_count_yellow = lv_count_yellow + 1.
            WHEN icon_green_light.
              lv_count_green = lv_count_green + 1.
          ENDCASE.
        ENDLOOP.

        IF lv_total_plan <> 0.
          lv_total_usage = ( lv_total_act / lv_total_plan ) * 100.
        ENDIF.
        lv_order_cnt = lines( mt_department_orders ).

        SORT mt_department_orders BY usage DESCENDING.

        SKIP.
  ULINE /1(103). " ➔ 換行，精準畫 103 格
        FORMAT COLOR COL_HEADING INTENSIFIED ON.
        WRITE: / '|', (101) '部門彙總 Dashboard' CENTERED, '|'. " ➔ 103 - 2(外框) = 101
        FORMAT COLOR OFF.

        ULINE /1(103).
        FORMAT COLOR COL_HEADING.
        WRITE: / '|', (16) '指標', '|', (16) '數值',
                 '|', (16) '指標', '|', (16) '數值',
                 '|', (16) '指標', '|', (16) '數值', '|'.
        FORMAT COLOR OFF.

        ULINE /1(103).
        WRITE: / '|', (16) '部門', '|', (16) gv_dialog_dept_name,
                 '|', (16) '成本中心', '|', (16) iv_kostv,
                 '|', (16) '訂單數', '|', (16) lv_order_cnt, '|'.

        ULINE /1(103).
        WRITE: / '|', (16) '總預算(USD)', '|', (16) lv_total_plan CURRENCY 'USD',
                 '|', (16) '總實際(USD)', '|', (16) lv_total_act CURRENCY 'USD',
                 '|', (16) '整體執行率%', '|', (16) lv_total_usage DECIMALS 2, '|'.

        ULINE /1(103).
        WRITE: / '|', (16) '紅燈' COLOR COL_NEGATIVE, '|', (16) lv_count_red COLOR COL_NEGATIVE,
                 '|', (16) '黃燈' COLOR COL_TOTAL,    '|', (16) lv_count_yellow COLOR COL_TOTAL,
                 '|', (16) '綠燈' COLOR COL_POSITIVE, '|', (16) lv_count_green COLOR COL_POSITIVE, '|'.

        ULINE /1(103). "

        ULINE AT (108).
        FORMAT COLOR COL_HEADING.
        WRITE: / '|', (4) '狀態', '|', (12) '內部訂單', '|', (34) '描述',
              '|', (14) '預算(USD)', '|', (14) '實際(USD)', '|', (8) '執行率%',
              '|', (14) '差異(USD)', '|'.
        FORMAT COLOR OFF.
        ULINE AT (108).

        LOOP AT mt_department_orders INTO DATA(ls_order).
          lv_ktext_disp = me->sanitize_text( ls_order-ktext ).
          lv_variance = ls_order-plan_amt - ls_order-act_amt.

          IF ls_order-usage >= 100.
            FORMAT COLOR COL_NEGATIVE.
          ELSEIF ls_order-usage >= 80.
            FORMAT COLOR COL_TOTAL.
          ELSE.
            FORMAT COLOR OFF.
          ENDIF.

          WRITE: / '|', (4) ls_order-light AS ICON,
               '|', (12) ls_order-aufnr,
               '|', (34) lv_ktext_disp,
               '|', (14) ls_order-plan_amt CURRENCY 'USD',
               '|', (14) ls_order-act_amt CURRENCY 'USD',
               '|', (8) ls_order-usage DECIMALS 2,
               '|', (14) lv_variance CURRENCY 'USD', '|'.

          FORMAT COLOR OFF.
        ENDLOOP.
        ULINE AT (108).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* 啟動與事件
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
SELECT-OPTIONS: s_aufnr FOR aufk-aufnr.
PARAMETERS:     p_kokrs TYPE aufk-kokrs DEFAULT 'NA00' OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

DATA: go_report TYPE REF TO lcl_report.

START-OF-SELECTION.
  CREATE OBJECT go_report.
  go_report->get_data_l1( it_aufnr = s_aufnr[] iv_kokrs = p_kokrs ).
  IF go_report->mt_level1 IS INITIAL.
    MESSAGE '查無符合條件的內部訂單資料，請調整查詢條件' TYPE 'I'.
    RETURN.
  ENDIF.
  go_report->display_l1( ).

AT LINE-SELECTION.
  " 🚀 終極魔法：直接看使用者滑鼠點擊畫面的「物理座標第幾格」(sy-cucol)
  " 版面縮到 100 欄後，右側按鈕區以第 86 欄作為判斷邊界
  IF sy-cucol >= 86 AND gv_hide_summ_aufnr IS NOT INITIAL.
    go_report->open_department_dialog( iv_aufnr = gv_hide_summ_aufnr ).
    CLEAR: gv_hide_summ_aufnr, gv_hide_aufnr.

  " 左側為內部訂單點擊區
  ELSEIF sy-cucol < 86 AND gv_hide_aufnr IS NOT INITIAL.
    CASE sy-lsind.
      WHEN 1.
        go_report->get_data_l2( gv_hide_aufnr ).
        go_report->display_l2( gv_hide_aufnr ).
        CLEAR: gv_hide_aufnr, gv_hide_summ_aufnr.
    ENDCASE.

  " 情況 3：使用者在第二層雙擊「成本要素」
  ELSEIF gv_hide_kstar IS NOT INITIAL.
    CASE sy-lsind.
      WHEN 2.
        go_report->jump_ka03( iv_kstar = gv_hide_kstar iv_kokrs = p_kokrs ).
        CLEAR gv_hide_kstar.
        sy-lsind = 1.
    ENDCASE.
  ENDIF.

*----------------------------------------------------------------------*
* Dynpro 橋樑模組 (PBO / PAI)
*----------------------------------------------------------------------*
MODULE status_0100 OUTPUT.
  SET PF-STATUS 'ZD100'.
  SET TITLEBAR 'T100' WITH gv_dialog_dept_name.
ENDMODULE.

MODULE user_command_0100 INPUT.
  CASE gv_dialog_okcode.
    WHEN 'SUMM'.
      IF gv_dialog_kostl IS INITIAL.
        MESSAGE '成本中心為空白，無法顯示部門彙總' TYPE 'I'.
        CLEAR gv_dialog_okcode.
        RETURN.
      ENDIF.
      gv_show_summary = abap_true.
      CALL SCREEN c_screen_history.
      CLEAR gv_dialog_okcode.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.

MODULE status_0200 OUTPUT.
  SUPPRESS DIALOG.
  LEAVE TO LIST-PROCESSING AND RETURN TO SCREEN c_screen_budget.
ENDMODULE.

MODULE user_command_0200 INPUT.
  IF gv_show_summary = abap_true.
    go_report->display_department_orders(
      iv_kostv = gv_dialog_kostl
      iv_kokrs = p_kokrs ).
    IF go_report->mt_department_orders IS INITIAL.
      MESSAGE '此成本中心目前沒有可顯示的內部訂單' TYPE 'I'.
    ENDIF.
    gv_show_summary = abap_false.
  ENDIF.
  LEAVE TO SCREEN c_screen_budget.
ENDMODULE.
