*&---------------------------------------------------------------------*
*& Report ZINVOICE_OVERVIEW
*&---------------------------------------------------------------------*
*& Faktura-Uebersichtsreport
*&
*& Dieser Report zeigt drei Bereiche:
*& 1. Lieferungen, die noch nicht fakturiert wurden
*& 2. Auftraege, die auftragsbezogen fakturiert werden koennen
*& 3. Fakturen, die noch nicht in der Buchhaltung gebucht sind
*&
*& Verwendete SAP-Tabellen:
*&   LIKP/LIPS - Lieferung (Kopf/Position)
*&   VBAK/VBAP - Kundenauftrag (Kopf/Position)
*&   VBRK      - Faktura (Kopf)
*&   VBUP      - Positionsstatus (ECC) / Kompatibilitaetsview (S/4HANA)
*&   KNA1      - Kundenstamm
*&---------------------------------------------------------------------*
REPORT zinvoice_overview LINE-SIZE 255.

TYPE-POOLS: slis.

*----------------------------------------------------------------------*
* Constants
*----------------------------------------------------------------------*
CONSTANTS:
  gc_ampel_red    TYPE c LENGTH 1 VALUE '1',
  gc_ampel_yellow TYPE c LENGTH 1 VALUE '2',
  gc_ampel_green  TYPE c LENGTH 1 VALUE '3'.

*----------------------------------------------------------------------*
* Type Definitions
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_delivery,
    ampel     TYPE c LENGTH 1,
    vbeln     TYPE vbeln,
    posnr     TYPE posnr,
    erdat     TYPE erdat,
    lfdat     TYPE lfdat,
    wadat_ist TYPE wadat_ist,
    kunnr     TYPE kunnr,
    name1     TYPE name1_gp,
    matnr     TYPE matnr,
    arktx     TYPE arktx,
    lfimg     TYPE lfimg,
    vrkme     TYPE vrkme,
    vgbel     TYPE vgbel,
    vgpos     TYPE vgpos,
    fksta     TYPE fksta,
    fksta_txt TYPE char20,
  END OF ty_delivery,

  BEGIN OF ty_order,
    ampel     TYPE c LENGTH 1,
    vbeln     TYPE vbeln,
    posnr     TYPE posnr,
    audat     TYPE audat,
    auart     TYPE auart,
    kunnr     TYPE kunnr,
    name1     TYPE name1_gp,
    matnr     TYPE matnr,
    arktx     TYPE arktx,
    kwmeng    TYPE kwmeng,
    vrkme     TYPE vrkme,
    netwr     TYPE netwr_ap,
    waerk     TYPE waerk,
    fkrel     TYPE fkrel,
    fksta     TYPE fksta,
    fksta_txt TYPE char20,
  END OF ty_order,

  BEGIN OF ty_billing,
    ampel     TYPE c LENGTH 1,
    vbeln     TYPE vbeln,
    fkdat     TYPE fkdat,
    fkart     TYPE fkart,
    kunag     TYPE kunag,
    name1     TYPE name1_gp,
    netwr     TYPE netwr_vf,
    waerk     TYPE waerk,
    mwsbk     TYPE mwsbk,
    rfbsk     TYPE rfbsk,
    rfbsk_txt TYPE char30,
    erdat     TYPE erdat,
    ernam     TYPE ernam,
    bukrs     TYPE bukrs,
  END OF ty_billing.

*----------------------------------------------------------------------*
* Global Data
*----------------------------------------------------------------------*
DATA:
  gt_delivery TYPE STANDARD TABLE OF ty_delivery,
  gt_order    TYPE STANDARD TABLE OF ty_order,
  gt_billing  TYPE STANDARD TABLE OF ty_billing.

* Reference fields for select-options
DATA:
  gv_vkorg TYPE vkorg,
  gv_vtweg TYPE vtweg,
  gv_spart TYPE spart,
  gv_kunnr TYPE kunnr,
  gv_bukrs TYPE bukrs,
  gv_lfdat TYPE lfdat,
  gv_audat TYPE audat,
  gv_fkdat TYPE fkdat.

* Block titles (set in INITIALIZATION)
DATA:
  gv_t_b01 TYPE char40,
  gv_t_b02 TYPE char40,
  gv_t_b03 TYPE char40,
  gv_t_b04 TYPE char40.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE gv_t_b01.
  SELECT-OPTIONS:
    s_vkorg FOR gv_vkorg OBLIGATORY,
    s_vtweg FOR gv_vtweg,
    s_spart FOR gv_spart,
    s_bukrs FOR gv_bukrs.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE gv_t_b02.
  SELECT-OPTIONS:
    s_kunnr FOR gv_kunnr.
SELECTION-SCREEN END OF BLOCK b02.

SELECTION-SCREEN BEGIN OF BLOCK b03 WITH FRAME TITLE gv_t_b03.
  SELECT-OPTIONS:
    s_lfdat FOR gv_lfdat,
    s_audat FOR gv_audat,
    s_fkdat FOR gv_fkdat.
SELECTION-SCREEN END OF BLOCK b03.

SELECTION-SCREEN BEGIN OF BLOCK b04 WITH FRAME TITLE gv_t_b04.
  PARAMETERS:
    p_deliv AS CHECKBOX DEFAULT 'X' USER-COMMAND uc1,
    p_order AS CHECKBOX DEFAULT 'X' USER-COMMAND uc2,
    p_billi AS CHECKBOX DEFAULT 'X' USER-COMMAND uc3.
SELECTION-SCREEN END OF BLOCK b04.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  gv_t_b01 = 'Organisationsdaten'.
  gv_t_b02 = 'Partner'.
  gv_t_b03 = 'Datumseingrenzung'.
  gv_t_b04 = 'Anzeigeoptionen'.

  %_s_vkorg_%_app_%-text = 'Verkaufsorg.'.
  %_s_vtweg_%_app_%-text = 'Vertriebsweg'.
  %_s_spart_%_app_%-text = 'Sparte'.
  %_s_bukrs_%_app_%-text = 'Buchungskreis'.
  %_s_kunnr_%_app_%-text = 'Kunde'.
  %_s_lfdat_%_app_%-text = 'Lieferdatum'.
  %_s_audat_%_app_%-text = 'Auftragsdatum'.
  %_s_fkdat_%_app_%-text = 'Fakturadatum'.
  %_p_deliv_%_app_%-text = 'Nicht fakt. Lieferungen'.
  %_p_order_%_app_%-text = 'Auftragsb. fakturierbar'.
  %_p_billi_%_app_%-text = 'Offene Fakturen (FI)'.

*----------------------------------------------------------------------*
* AT SELECTION-SCREEN
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  LOOP AT s_vkorg.
    AUTHORITY-CHECK OBJECT 'V_VBRK_VKO'
      ID 'VKORG' FIELD s_vkorg-low
      ID 'VTWEG' DUMMY
      ID 'SPART' DUMMY
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE e047(v1) WITH s_vkorg-low.
    ENDIF.
  ENDLOOP.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  IF p_deliv = abap_true.
    PERFORM select_deliveries.
  ENDIF.

  IF p_order = abap_true.
    PERFORM select_orders.
  ENDIF.

  IF p_billi = abap_true.
    PERFORM select_billings.
  ENDIF.

  " Enrich all tables with customer names in one pass
  PERFORM enrich_customer_names.

*----------------------------------------------------------------------*
* END-OF-SELECTION
*----------------------------------------------------------------------*
END-OF-SELECTION.

  IF   gt_delivery IS INITIAL
   AND gt_order    IS INITIAL
   AND gt_billing  IS INITIAL.
    MESSAGE s398(00) WITH 'Keine Daten zur Selektion gefunden' space space space.
    RETURN.
  ENDIF.

  PERFORM display_results.


*&---------------------------------------------------------------------*
*& Form SELECT_DELIVERIES
*&---------------------------------------------------------------------*
*& Selektiert Lieferungen, die noch nicht (vollstaendig) fakturiert sind.
*& VBUP-FKSTA: A = Nicht fakturiert, B = Teilweise fakturiert
*&---------------------------------------------------------------------*
FORM select_deliveries.

  SELECT l~vbeln p~posnr l~erdat l~lfdat l~wadat_ist l~kunnr
         p~matnr p~arktx p~lfimg p~vrkme p~vgbel p~vgpos
         u~fksta
    INTO CORRESPONDING FIELDS OF TABLE gt_delivery
    FROM likp AS l
    INNER JOIN lips AS p ON p~vbeln = l~vbeln
    INNER JOIN vbup AS u ON u~vbeln = p~vbeln
                        AND u~posnr = p~posnr
    WHERE p~vkorg IN s_vkorg
      AND p~vtweg IN s_vtweg
      AND p~spart IN s_spart
      AND l~lfdat IN s_lfdat
      AND l~kunnr IN s_kunnr
      AND ( u~fksta = 'A' OR u~fksta = 'B' )
      AND p~lfimg > 0.

  CHECK gt_delivery IS NOT INITIAL.

  " Set traffic light and status text
  FIELD-SYMBOLS: <fs_del> TYPE ty_delivery.

  LOOP AT gt_delivery ASSIGNING <fs_del>.
    CASE <fs_del>-fksta.
      WHEN 'A'.
        <fs_del>-fksta_txt = 'Nicht fakturiert'.
        IF <fs_del>-wadat_ist IS NOT INITIAL.
          " Warenausgang gebucht aber nicht fakturiert -> Rot
          <fs_del>-ampel = gc_ampel_red.
        ELSE.
          " Warenausgang noch nicht gebucht -> Gelb
          <fs_del>-ampel = gc_ampel_yellow.
        ENDIF.
      WHEN 'B'.
        <fs_del>-fksta_txt = 'Teilw. fakturiert'.
        <fs_del>-ampel = gc_ampel_yellow.
    ENDCASE.
  ENDLOOP.

  SORT gt_delivery BY kunnr vbeln posnr.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SELECT_ORDERS
*&---------------------------------------------------------------------*
*& Selektiert Auftraege, die auftragsbezogen fakturiert werden koennen.
*& VBAP-FKREL = 'B' -> Auftragsbezogene Faktura
*& VBUP-FKSTA: A = Nicht fakturiert, B = Teilweise fakturiert
*&---------------------------------------------------------------------*
FORM select_orders.

  SELECT k~vbeln p~posnr k~audat k~auart k~kunnr
         p~matnr p~arktx p~kwmeng p~vrkme
         p~netwr k~waerk p~fkrel u~fksta
    INTO CORRESPONDING FIELDS OF TABLE gt_order
    FROM vbak AS k
    INNER JOIN vbap AS p ON p~vbeln = k~vbeln
    INNER JOIN vbup AS u ON u~vbeln = p~vbeln
                        AND u~posnr = p~posnr
    WHERE k~vkorg IN s_vkorg
      AND k~vtweg IN s_vtweg
      AND k~spart IN s_spart
      AND k~audat IN s_audat
      AND k~kunnr IN s_kunnr
      AND p~fkrel = 'B'
      AND ( u~fksta = 'A' OR u~fksta = 'B' )
      AND p~abgru = space.

  CHECK gt_order IS NOT INITIAL.

  " Set traffic light and status text
  FIELD-SYMBOLS: <fs_ord> TYPE ty_order.

  LOOP AT gt_order ASSIGNING <fs_ord>.
    CASE <fs_ord>-fksta.
      WHEN 'A'.
        <fs_ord>-fksta_txt = 'Nicht fakturiert'.
        <fs_ord>-ampel = gc_ampel_yellow.
      WHEN 'B'.
        <fs_ord>-fksta_txt = 'Teilw. fakturiert'.
        <fs_ord>-ampel = gc_ampel_green.
    ENDCASE.
  ENDLOOP.

  SORT gt_order BY kunnr vbeln posnr.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SELECT_BILLINGS
*&---------------------------------------------------------------------*
*& Selektiert Fakturen, die noch nicht in die Buchhaltung uebertragen
*& wurden.
*& VBRK-RFBSK: ' '/A = Nicht uebertragen, B = Fehlerhaft, C = Gebucht
*&---------------------------------------------------------------------*
FORM select_billings.

  SELECT vbeln fkdat fkart kunag netwr waerk mwsbk
         rfbsk erdat ernam bukrs
    INTO CORRESPONDING FIELDS OF TABLE gt_billing
    FROM vbrk
    WHERE vkorg IN s_vkorg
      AND vtweg IN s_vtweg
      AND spart IN s_spart
      AND fkdat IN s_fkdat
      AND kunag IN s_kunnr
      AND bukrs IN s_bukrs
      AND rfbsk <> 'C'
      AND fksto <> 'X'.

  CHECK gt_billing IS NOT INITIAL.

  " Set traffic light and status text
  FIELD-SYMBOLS: <fs_bil> TYPE ty_billing.

  LOOP AT gt_billing ASSIGNING <fs_bil>.
    CASE <fs_bil>-rfbsk.
      WHEN space.
        <fs_bil>-rfbsk_txt = 'Nicht uebertragen'.
        <fs_bil>-ampel = gc_ampel_yellow.
      WHEN 'A'.
        <fs_bil>-rfbsk_txt = 'Nicht uebertragen'.
        <fs_bil>-ampel = gc_ampel_yellow.
      WHEN 'B'.
        <fs_bil>-rfbsk_txt = 'Fehlerhaft'.
        <fs_bil>-ampel = gc_ampel_red.
    ENDCASE.
  ENDLOOP.

  SORT gt_billing BY bukrs vbeln.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form ENRICH_CUSTOMER_NAMES
*&---------------------------------------------------------------------*
*& Liest Kundennamen aus KNA1 fuer alle drei Ergebnistabellen.
*&---------------------------------------------------------------------*
FORM enrich_customer_names.

  TYPES: BEGIN OF ty_kna1,
           kunnr TYPE kunnr,
           name1 TYPE name1_gp,
         END OF ty_kna1.

  DATA: lt_kunnr TYPE STANDARD TABLE OF kunnr,
        lt_kna1  TYPE SORTED TABLE OF ty_kna1 WITH UNIQUE KEY kunnr,
        ls_kna1  TYPE ty_kna1.

  FIELD-SYMBOLS: <fs_del> TYPE ty_delivery,
                 <fs_ord> TYPE ty_order,
                 <fs_bil> TYPE ty_billing.

  " Collect all unique customer numbers
  LOOP AT gt_delivery ASSIGNING <fs_del>.
    APPEND <fs_del>-kunnr TO lt_kunnr.
  ENDLOOP.

  LOOP AT gt_order ASSIGNING <fs_ord>.
    APPEND <fs_ord>-kunnr TO lt_kunnr.
  ENDLOOP.

  LOOP AT gt_billing ASSIGNING <fs_bil>.
    APPEND <fs_bil>-kunag TO lt_kunnr.
  ENDLOOP.

  SORT lt_kunnr.
  DELETE ADJACENT DUPLICATES FROM lt_kunnr.
  DELETE lt_kunnr WHERE table_line IS INITIAL.

  CHECK lt_kunnr IS NOT INITIAL.

  SELECT kunnr name1
    INTO CORRESPONDING FIELDS OF TABLE lt_kna1
    FROM kna1
    FOR ALL ENTRIES IN lt_kunnr
    WHERE kunnr = lt_kunnr-table_line.

  " Fill names into delivery table
  LOOP AT gt_delivery ASSIGNING <fs_del>.
    READ TABLE lt_kna1 INTO ls_kna1
      WITH KEY kunnr = <fs_del>-kunnr.
    IF sy-subrc = 0.
      <fs_del>-name1 = ls_kna1-name1.
    ENDIF.
  ENDLOOP.

  " Fill names into order table
  LOOP AT gt_order ASSIGNING <fs_ord>.
    READ TABLE lt_kna1 INTO ls_kna1
      WITH KEY kunnr = <fs_ord>-kunnr.
    IF sy-subrc = 0.
      <fs_ord>-name1 = ls_kna1-name1.
    ENDIF.
  ENDLOOP.

  " Fill names into billing table
  LOOP AT gt_billing ASSIGNING <fs_bil>.
    READ TABLE lt_kna1 INTO ls_kna1
      WITH KEY kunnr = <fs_bil>-kunag.
    IF sy-subrc = 0.
      <fs_bil>-name1 = ls_kna1-name1.
    ENDIF.
  ENDLOOP.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form DISPLAY_RESULTS
*&---------------------------------------------------------------------*
*& Zeigt die drei Ergebnisbloecke als ALV Block List an.
*&---------------------------------------------------------------------*
FORM display_results.

  DATA: ls_layout TYPE slis_layout_alv,
        lt_fcat   TYPE slis_t_fieldcat_alv,
        lt_events TYPE slis_t_event,
        ls_event  TYPE slis_alv_event.

  " Initialize ALV block list
  CALL FUNCTION 'REUSE_ALV_BLOCK_LIST_INIT'
    EXPORTING
      i_callback_program      = sy-repid
      i_callback_user_command = 'USER_COMMAND'.

  "--------------------------------------------------------------
  " Block 1: Nicht fakturierte Lieferungen
  "--------------------------------------------------------------
  IF gt_delivery IS NOT INITIAL.
    CLEAR: lt_fcat, lt_events, ls_layout.

    PERFORM build_fcat_delivery CHANGING lt_fcat.

    ls_layout-colwidth_optimize = 'X'.
    ls_layout-lights_fieldname  = 'AMPEL'.

    CLEAR ls_event.
    ls_event-name = 'TOP_OF_PAGE'.
    ls_event-form = 'TOP_DELIVERY'.
    APPEND ls_event TO lt_events.

    CALL FUNCTION 'REUSE_ALV_BLOCK_LIST_APPEND'
      EXPORTING
        is_layout   = ls_layout
        it_fieldcat = lt_fcat
        i_tabname   = 'GT_DELIVERY'
        it_events   = lt_events
      TABLES
        t_outtab    = gt_delivery.
  ENDIF.

  "--------------------------------------------------------------
  " Block 2: Auftragsbezogen fakturierbare Auftraege
  "--------------------------------------------------------------
  IF gt_order IS NOT INITIAL.
    CLEAR: lt_fcat, lt_events, ls_layout.

    PERFORM build_fcat_order CHANGING lt_fcat.

    ls_layout-colwidth_optimize = 'X'.
    ls_layout-lights_fieldname  = 'AMPEL'.

    CLEAR ls_event.
    ls_event-name = 'TOP_OF_PAGE'.
    ls_event-form = 'TOP_ORDER'.
    APPEND ls_event TO lt_events.

    CALL FUNCTION 'REUSE_ALV_BLOCK_LIST_APPEND'
      EXPORTING
        is_layout   = ls_layout
        it_fieldcat = lt_fcat
        i_tabname   = 'GT_ORDER'
        it_events   = lt_events
      TABLES
        t_outtab    = gt_order.
  ENDIF.

  "--------------------------------------------------------------
  " Block 3: Fakturen nicht in Buchhaltung gebucht
  "--------------------------------------------------------------
  IF gt_billing IS NOT INITIAL.
    CLEAR: lt_fcat, lt_events, ls_layout.

    PERFORM build_fcat_billing CHANGING lt_fcat.

    ls_layout-colwidth_optimize = 'X'.
    ls_layout-lights_fieldname  = 'AMPEL'.

    CLEAR ls_event.
    ls_event-name = 'TOP_OF_PAGE'.
    ls_event-form = 'TOP_BILLING'.
    APPEND ls_event TO lt_events.

    CALL FUNCTION 'REUSE_ALV_BLOCK_LIST_APPEND'
      EXPORTING
        is_layout   = ls_layout
        it_fieldcat = lt_fcat
        i_tabname   = 'GT_BILLING'
        it_events   = lt_events
      TABLES
        t_outtab    = gt_billing.
  ENDIF.

  " Display all blocks
  CALL FUNCTION 'REUSE_ALV_BLOCK_LIST_DISPLAY'.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form BUILD_FCAT_DELIVERY
*&---------------------------------------------------------------------*
FORM build_fcat_delivery CHANGING ct_fcat TYPE slis_t_fieldcat_alv.

  DATA: ls TYPE slis_fieldcat_alv.

  CLEAR ct_fcat.

  CLEAR ls. ls-fieldname = 'VBELN'.     ls-seltext_l = 'Lieferung'.       ls-outputlen = 10. ls-hotspot = 'X'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'POSNR'.     ls-seltext_l = 'Position'.        ls-outputlen = 6.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'ERDAT'.     ls-seltext_l = 'Angelegt am'.     ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'LFDAT'.     ls-seltext_l = 'Lieferdatum'.     ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'WADAT_IST'. ls-seltext_l = 'WA-Datum'.        ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'KUNNR'.     ls-seltext_l = 'Kunde'.           ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'NAME1'.     ls-seltext_l = 'Kundenname'.      ls-outputlen = 30. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'MATNR'.     ls-seltext_l = 'Material'.        ls-outputlen = 18. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'ARKTX'.     ls-seltext_l = 'Bezeichnung'.     ls-outputlen = 30. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'LFIMG'.     ls-seltext_l = 'Liefermenge'.     ls-outputlen = 13. ls-do_sum = 'X'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'VRKME'.     ls-seltext_l = 'ME'.              ls-outputlen = 4.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'VGBEL'.     ls-seltext_l = 'Auftrag'.         ls-outputlen = 10. ls-hotspot = 'X'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'VGPOS'.     ls-seltext_l = 'Auftr.Pos'.       ls-outputlen = 6.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'FKSTA_TXT'. ls-seltext_l = 'Fakturastatus'.   ls-outputlen = 20. APPEND ls TO ct_fcat.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form BUILD_FCAT_ORDER
*&---------------------------------------------------------------------*
FORM build_fcat_order CHANGING ct_fcat TYPE slis_t_fieldcat_alv.

  DATA: ls TYPE slis_fieldcat_alv.

  CLEAR ct_fcat.

  CLEAR ls. ls-fieldname = 'VBELN'.     ls-seltext_l = 'Auftrag'.            ls-outputlen = 10. ls-hotspot = 'X'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'POSNR'.     ls-seltext_l = 'Position'.           ls-outputlen = 6.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'AUDAT'.     ls-seltext_l = 'Auftragsdatum'.      ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'AUART'.     ls-seltext_l = 'Auftragsart'.        ls-outputlen = 6.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'KUNNR'.     ls-seltext_l = 'Kunde'.              ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'NAME1'.     ls-seltext_l = 'Kundenname'.         ls-outputlen = 30. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'MATNR'.     ls-seltext_l = 'Material'.           ls-outputlen = 18. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'ARKTX'.     ls-seltext_l = 'Bezeichnung'.        ls-outputlen = 30. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'KWMENG'.    ls-seltext_l = 'Auftragsmenge'.      ls-outputlen = 13. ls-do_sum = 'X'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'VRKME'.     ls-seltext_l = 'ME'.                 ls-outputlen = 4.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'NETWR'.     ls-seltext_l = 'Nettowert'.          ls-outputlen = 15. ls-do_sum = 'X'. ls-cfieldname = 'WAERK'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'WAERK'.     ls-seltext_l = 'Waehr.'.             ls-outputlen = 5.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'FKSTA_TXT'. ls-seltext_l = 'Fakturastatus'.      ls-outputlen = 20. APPEND ls TO ct_fcat.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form BUILD_FCAT_BILLING
*&---------------------------------------------------------------------*
FORM build_fcat_billing CHANGING ct_fcat TYPE slis_t_fieldcat_alv.

  DATA: ls TYPE slis_fieldcat_alv.

  CLEAR ct_fcat.

  CLEAR ls. ls-fieldname = 'VBELN'.     ls-seltext_l = 'Faktura'.             ls-outputlen = 10. ls-hotspot = 'X'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'FKDAT'.     ls-seltext_l = 'Fakturadatum'.        ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'FKART'.     ls-seltext_l = 'Fakturaart'.          ls-outputlen = 6.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'BUKRS'.     ls-seltext_l = 'Buchungskreis'.       ls-outputlen = 6.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'KUNAG'.     ls-seltext_l = 'Auftraggeber'.        ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'NAME1'.     ls-seltext_l = 'Kundenname'.          ls-outputlen = 30. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'NETWR'.     ls-seltext_l = 'Nettowert'.           ls-outputlen = 15. ls-do_sum = 'X'. ls-cfieldname = 'WAERK'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'MWSBK'.     ls-seltext_l = 'Steuerbetrag'.        ls-outputlen = 15. ls-do_sum = 'X'. ls-cfieldname = 'WAERK'. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'WAERK'.     ls-seltext_l = 'Waehr.'.              ls-outputlen = 5.  APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'RFBSK_TXT'. ls-seltext_l = 'Buchungsstatus'.      ls-outputlen = 20. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'ERDAT'.     ls-seltext_l = 'Angelegt am'.         ls-outputlen = 10. APPEND ls TO ct_fcat.
  CLEAR ls. ls-fieldname = 'ERNAM'.     ls-seltext_l = 'Angelegt von'.        ls-outputlen = 12. APPEND ls TO ct_fcat.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form TOP_DELIVERY
*&---------------------------------------------------------------------*
*& ALV Block Header: Nicht fakturierte Lieferungen
*&---------------------------------------------------------------------*
FORM top_delivery.                                          "#EC CALLED

  DATA: lt_header TYPE slis_t_listheader,
        ls_header TYPE slis_listheader,
        lv_count  TYPE i,
        lv_text   TYPE char60.

  ls_header-typ  = 'H'.
  ls_header-info = 'Nicht fakturierte Lieferungen'.
  APPEND ls_header TO lt_header.

  DESCRIBE TABLE gt_delivery LINES lv_count.
  WRITE lv_count TO lv_text LEFT-JUSTIFIED.
  CONCATENATE 'Anzahl Positionen:' lv_text INTO lv_text SEPARATED BY space.
  CLEAR ls_header.
  ls_header-typ  = 'S'.
  ls_header-key  = 'Ergebnis'.
  ls_header-info = lv_text.
  APPEND ls_header TO lt_header.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_header.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form TOP_ORDER
*&---------------------------------------------------------------------*
*& ALV Block Header: Auftragsbezogen fakturierbare Auftraege
*&---------------------------------------------------------------------*
FORM top_order.                                             "#EC CALLED

  DATA: lt_header TYPE slis_t_listheader,
        ls_header TYPE slis_listheader,
        lv_count  TYPE i,
        lv_text   TYPE char60.

  ls_header-typ  = 'H'.
  ls_header-info = 'Auftragsbezogen fakturierbare Auftraege'.
  APPEND ls_header TO lt_header.

  DESCRIBE TABLE gt_order LINES lv_count.
  WRITE lv_count TO lv_text LEFT-JUSTIFIED.
  CONCATENATE 'Anzahl Positionen:' lv_text INTO lv_text SEPARATED BY space.
  CLEAR ls_header.
  ls_header-typ  = 'S'.
  ls_header-key  = 'Ergebnis'.
  ls_header-info = lv_text.
  APPEND ls_header TO lt_header.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_header.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form TOP_BILLING
*&---------------------------------------------------------------------*
*& ALV Block Header: Fakturen nicht in Buchhaltung
*&---------------------------------------------------------------------*
FORM top_billing.                                           "#EC CALLED

  DATA: lt_header TYPE slis_t_listheader,
        ls_header TYPE slis_listheader,
        lv_count  TYPE i,
        lv_text   TYPE char60.

  ls_header-typ  = 'H'.
  ls_header-info = 'Fakturen - nicht in Buchhaltung gebucht'.
  APPEND ls_header TO lt_header.

  DESCRIBE TABLE gt_billing LINES lv_count.
  WRITE lv_count TO lv_text LEFT-JUSTIFIED.
  CONCATENATE 'Anzahl Positionen:' lv_text INTO lv_text SEPARATED BY space.
  CLEAR ls_header.
  ls_header-typ  = 'S'.
  ls_header-key  = 'Ergebnis'.
  ls_header-info = lv_text.
  APPEND ls_header TO lt_header.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_header.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form USER_COMMAND
*&---------------------------------------------------------------------*
*& Callback fuer Doppelklick/Hotspot-Navigation in den ALV-Bloecken.
*& Navigiert zum jeweiligen Beleg (VL03N, VA03, VF03).
*&---------------------------------------------------------------------*
FORM user_command USING r_ucomm     LIKE sy-ucomm
                        rs_selfield TYPE slis_selfield.     "#EC CALLED

  DATA: lv_vbeln TYPE vbeln.

  CHECK r_ucomm = '&IC1'.  " Hotspot click

  lv_vbeln = rs_selfield-value.

  CASE rs_selfield-tabname.

    WHEN 'GT_DELIVERY'.
      CASE rs_selfield-fieldname.
        WHEN 'VBELN'.
          SET PARAMETER ID 'VL' FIELD lv_vbeln.
          CALL TRANSACTION 'VL03N' AND SKIP FIRST SCREEN.
        WHEN 'VGBEL'.
          SET PARAMETER ID 'AUN' FIELD lv_vbeln.
          CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN.
      ENDCASE.

    WHEN 'GT_ORDER'.
      IF rs_selfield-fieldname = 'VBELN'.
        SET PARAMETER ID 'AUN' FIELD lv_vbeln.
        CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN.
      ENDIF.

    WHEN 'GT_BILLING'.
      IF rs_selfield-fieldname = 'VBELN'.
        SET PARAMETER ID 'VF' FIELD lv_vbeln.
        CALL TRANSACTION 'VF03' AND SKIP FIRST SCREEN.
      ENDIF.

  ENDCASE.

ENDFORM.
