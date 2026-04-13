*&---------------------------------------------------------------------*
*& Include /MBSO/ZINVOICE_OVERVIEW_CL1
*&---------------------------------------------------------------------*
*& Verarbeitungslogik: Selektion, Anreicherung und ALV-Anzeige
*&---------------------------------------------------------------------*


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
    WHERE l~vkorg IN s_vkorg
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
        lv_text   TYPE char70.

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
        lv_text   TYPE char70.

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
        lv_text   TYPE char70.

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


*&---------------------------------------------------------------------*
*& Form BUILD_CSV_CONTENT
*&---------------------------------------------------------------------*
*& Erzeugt den CSV-Inhalt (Semikolon-getrennt) fuer alle drei Bloecke.
*& Wird von Excel-Export und E-Mail-Versand gemeinsam genutzt.
*&---------------------------------------------------------------------*
FORM build_csv_content CHANGING ct_csv TYPE string_table.

  DATA: lv_line  TYPE string,
        lv_lfimg TYPE char20,
        lv_kwmng TYPE char20,
        lv_netwr TYPE char20,
        lv_mwsbk TYPE char20.

  FIELD-SYMBOLS: <fs_del> TYPE ty_delivery,
                 <fs_ord> TYPE ty_order,
                 <fs_bil> TYPE ty_billing.

  CLEAR ct_csv.

  "--- Block 1: Nicht fakturierte Lieferungen ---
  IF gt_delivery IS NOT INITIAL.
    APPEND 'Nicht fakturierte Lieferungen' TO ct_csv.

    CONCATENATE
      'Lieferung' 'Position' 'Angelegt am' 'Lieferdatum'
      'WA-Datum' 'Kunde' 'Kundenname' 'Material'
      'Bezeichnung' 'Liefermenge' 'ME' 'Auftrag'
      'Auftr.Pos' 'Fakturastatus'
      INTO lv_line SEPARATED BY gc_csv_sep.
    APPEND lv_line TO ct_csv.

    LOOP AT gt_delivery ASSIGNING <fs_del>.
      WRITE <fs_del>-lfimg TO lv_lfimg LEFT-JUSTIFIED.
      CONCATENATE
        <fs_del>-vbeln <fs_del>-posnr <fs_del>-erdat <fs_del>-lfdat
        <fs_del>-wadat_ist <fs_del>-kunnr <fs_del>-name1 <fs_del>-matnr
        <fs_del>-arktx lv_lfimg <fs_del>-vrkme <fs_del>-vgbel
        <fs_del>-vgpos <fs_del>-fksta_txt
        INTO lv_line SEPARATED BY gc_csv_sep.
      APPEND lv_line TO ct_csv.
    ENDLOOP.

    APPEND space TO ct_csv.
  ENDIF.

  "--- Block 2: Auftragsbezogen fakturierbare Auftraege ---
  IF gt_order IS NOT INITIAL.
    APPEND 'Auftragsbezogen fakturierbare Auftraege' TO ct_csv.

    CONCATENATE
      'Auftrag' 'Position' 'Auftragsdatum' 'Auftragsart'
      'Kunde' 'Kundenname' 'Material' 'Bezeichnung'
      'Auftragsmenge' 'ME' 'Nettowert' 'Waehrung'
      'Fakturastatus'
      INTO lv_line SEPARATED BY gc_csv_sep.
    APPEND lv_line TO ct_csv.

    LOOP AT gt_order ASSIGNING <fs_ord>.
      WRITE <fs_ord>-kwmeng TO lv_kwmng LEFT-JUSTIFIED.
      WRITE <fs_ord>-netwr  TO lv_netwr LEFT-JUSTIFIED.
      CONCATENATE
        <fs_ord>-vbeln <fs_ord>-posnr <fs_ord>-audat <fs_ord>-auart
        <fs_ord>-kunnr <fs_ord>-name1 <fs_ord>-matnr <fs_ord>-arktx
        lv_kwmng <fs_ord>-vrkme lv_netwr <fs_ord>-waerk
        <fs_ord>-fksta_txt
        INTO lv_line SEPARATED BY gc_csv_sep.
      APPEND lv_line TO ct_csv.
    ENDLOOP.

    APPEND space TO ct_csv.
  ENDIF.

  "--- Block 3: Fakturen nicht in Buchhaltung ---
  IF gt_billing IS NOT INITIAL.
    APPEND 'Fakturen - nicht in Buchhaltung gebucht' TO ct_csv.

    CONCATENATE
      'Faktura' 'Fakturadatum' 'Fakturaart' 'Buchungskreis'
      'Auftraggeber' 'Kundenname' 'Nettowert' 'Steuerbetrag'
      'Waehrung' 'Buchungsstatus' 'Angelegt am' 'Angelegt von'
      INTO lv_line SEPARATED BY gc_csv_sep.
    APPEND lv_line TO ct_csv.

    LOOP AT gt_billing ASSIGNING <fs_bil>.
      WRITE <fs_bil>-netwr TO lv_netwr LEFT-JUSTIFIED.
      WRITE <fs_bil>-mwsbk TO lv_mwsbk LEFT-JUSTIFIED.
      CONCATENATE
        <fs_bil>-vbeln <fs_bil>-fkdat <fs_bil>-fkart <fs_bil>-bukrs
        <fs_bil>-kunag <fs_bil>-name1 lv_netwr lv_mwsbk
        <fs_bil>-waerk <fs_bil>-rfbsk_txt <fs_bil>-erdat <fs_bil>-ernam
        INTO lv_line SEPARATED BY gc_csv_sep.
      APPEND lv_line TO ct_csv.
    ENDLOOP.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form EXPORT_TO_EXCEL
*&---------------------------------------------------------------------*
*& Exportiert die Ergebnisse als CSV-Datei auf den lokalen Rechner.
*& Nur im Vordergrund (Dialog) moeglich.
*&---------------------------------------------------------------------*
FORM export_to_excel.

  DATA: lt_csv    TYPE string_table,
        lv_fname  TYPE string,
        lv_path   TYPE string,
        lv_fpath  TYPE string,
        lv_action TYPE i.

  PERFORM build_csv_content CHANGING lt_csv.

  " Datei-Speichern-Dialog anzeigen
  cl_gui_frontend_services=>file_save_dialog(
    EXPORTING
      default_extension = 'csv'
      default_file_name = 'Faktura_Uebersicht.csv'
      file_filter       = 'CSV (*.csv)|*.csv|Alle Dateien (*.*)|*.*'
    CHANGING
      filename    = lv_fname
      path        = lv_path
      fullpath    = lv_fpath
      user_action = lv_action
    EXCEPTIONS
      OTHERS      = 1 ).

  IF sy-subrc <> 0 OR lv_action <> cl_gui_frontend_services=>action_ok.
    RETURN.
  ENDIF.

  " CSV herunterladen (UTF-8 Codepage 4110)
  cl_gui_frontend_services=>gui_download(
    EXPORTING
      filename  = lv_fpath
      filetype  = 'ASC'
      codepage  = '4110'
    CHANGING
      data_tab  = lt_csv
    EXCEPTIONS
      OTHERS    = 1 ).

  IF sy-subrc = 0.
    MESSAGE s398(00) WITH 'Excel-Export erfolgreich gespeichert.' space space space.
  ELSE.
    MESSAGE s398(00) WITH 'Fehler beim Excel-Export.' space space space DISPLAY LIKE 'E'.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SEND_RESULTS_BY_EMAIL
*&---------------------------------------------------------------------*
*& Versendet die Ergebnisse als CSV-Anhang per E-Mail via CL_BCS.
*& Funktioniert im Dialog und im Hintergrundjob.
*&---------------------------------------------------------------------*
FORM send_results_by_email.

  DATA: lo_send_request TYPE REF TO cl_bcs,
        lo_document     TYPE REF TO cl_document_bcs,
        lo_recipient    TYPE REF TO if_recipient_bcs,
        lo_sender       TYPE REF TO cl_sapuser_bcs,
        lo_conv         TYPE REF TO cl_abap_conv_out_ce,
        lx_bcs          TYPE REF TO cx_bcs,
        lv_error        TYPE string.

  DATA: lt_body     TYPE bcsy_text,
        ls_body     TYPE soli,
        lt_csv      TYPE string_table,
        lv_csv_str  TYPE string,
        lv_xstr     TYPE xstring,
        lv_xstr_csv TYPE xstring,
        lt_solix    TYPE solix_tab,
        lv_subject  TYPE so_obj_des,
        lv_att_subj TYPE sood-objdes,
        lv_att_size TYPE so_obj_len,
        lv_sent     TYPE os_boolean,
        lv_count    TYPE i,
        lv_text     TYPE char50.

  DATA: lv_bom TYPE x LENGTH 3 VALUE 'EFBBBF'.

  " CSV-Inhalt erzeugen
  PERFORM build_csv_content CHANGING lt_csv.

  " CSV in einen String zusammenfuehren
  CONCATENATE LINES OF lt_csv
    INTO lv_csv_str
    SEPARATED BY cl_abap_char_utilities=>cr_lf.

  " In UTF-8 xstring konvertieren (mit BOM fuer Excel)
  lo_conv = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
  lo_conv->convert( EXPORTING data = lv_csv_str IMPORTING buffer = lv_xstr_csv ).
  lv_xstr = lv_bom.
  CONCATENATE lv_xstr lv_xstr_csv INTO lv_xstr IN BYTE MODE.

  " xstring in SOLIX-Tabelle konvertieren
  lt_solix = cl_bcs_convert=>xstring_to_solix( iv_xstring = lv_xstr ).
  lv_att_size = xstrlen( lv_xstr ).

  TRY.
      " Sendauftrag erzeugen
      lo_send_request = cl_bcs=>create_persistent( ).

      " E-Mail-Body aufbauen
      ls_body-line = 'Faktura-Uebersichtsreport'.
      APPEND ls_body TO lt_body.
      CLEAR ls_body.
      APPEND ls_body TO lt_body.

      DESCRIBE TABLE gt_delivery LINES lv_count.
      WRITE lv_count TO lv_text LEFT-JUSTIFIED.
      CONCATENATE 'Nicht fakturierte Lieferungen:' lv_text
        INTO ls_body-line SEPARATED BY space.
      APPEND ls_body TO lt_body.

      DESCRIBE TABLE gt_order LINES lv_count.
      WRITE lv_count TO lv_text LEFT-JUSTIFIED.
      CONCATENATE 'Auftragsbez. fakturierbar:' lv_text
        INTO ls_body-line SEPARATED BY space.
      APPEND ls_body TO lt_body.

      DESCRIBE TABLE gt_billing LINES lv_count.
      WRITE lv_count TO lv_text LEFT-JUSTIFIED.
      CONCATENATE 'Offene Fakturen (FI):' lv_text
        INTO ls_body-line SEPARATED BY space.
      APPEND ls_body TO lt_body.

      CLEAR ls_body.
      APPEND ls_body TO lt_body.
      ls_body-line = 'Details siehe Anlage.'.
      APPEND ls_body TO lt_body.

      " Dokument erzeugen
      lv_subject = 'Faktura-Uebersichtsreport'.
      lo_document = cl_document_bcs=>create_document(
        i_type    = 'RAW'
        i_text    = lt_body
        i_subject = lv_subject ).

      " CSV-Anhang hinzufuegen
      lv_att_subj = 'Faktura_Uebersicht.csv'.
      lo_document->add_attachment(
        i_attachment_type    = 'CSV'
        i_attachment_subject = lv_att_subj
        i_attachment_size    = lv_att_size
        i_att_content_hex    = lt_solix ).

      lo_send_request->set_document( lo_document ).

      " Absender setzen
      lo_sender = cl_sapuser_bcs=>create( sy-uname ).
      lo_send_request->set_sender( lo_sender ).

      " Empfaenger aus Selektion hinzufuegen
      LOOP AT s_email.
        lo_recipient = cl_cam_address_bcs=>create_internet_address(
          i_address_string = s_email-low ).
        lo_send_request->add_recipient(
          i_recipient = lo_recipient
          i_express   = 'X' ).
      ENDLOOP.

      " Sofort senden
      lo_send_request->set_send_immediately( 'X' ).
      lv_sent = lo_send_request->send( i_with_error_screen = 'X' ).

      IF lv_sent = abap_true.
        COMMIT WORK.
        MESSAGE s398(00) WITH 'E-Mail erfolgreich versendet.' space space space.
      ELSE.
        MESSAGE s398(00) WITH 'E-Mail konnte nicht versendet werden.'
          space space space DISPLAY LIKE 'E'.
      ENDIF.

    CATCH cx_bcs INTO lx_bcs.
      lv_error = lx_bcs->get_text( ).
      MESSAGE s398(00) WITH 'Fehler:' lv_error space space DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.
