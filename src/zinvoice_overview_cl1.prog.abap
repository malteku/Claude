*&---------------------------------------------------------------------*
*& Include /MBSO/ZINVOICE_OVERVIEW_CL1
*&---------------------------------------------------------------------*
*& Verarbeitungslogik: Selektion, Anreicherung, ALV-Anzeige (CL_SALV),
*& CSV-Export und E-Mail-Versand
*&---------------------------------------------------------------------*


*----------------------------------------------------------------------*
* Local ALV Event Handler Class
*----------------------------------------------------------------------*
CLASS lcl_alv_handler DEFINITION.

  PUBLIC SECTION.
    METHODS:
      constructor
        IMPORTING iv_mode TYPE c,
      on_link_click
        FOR EVENT link_click OF cl_salv_events_table
        IMPORTING row column.

  PRIVATE SECTION.
    DATA: mv_mode TYPE c LENGTH 1.

ENDCLASS.

CLASS lcl_alv_handler IMPLEMENTATION.

  METHOD constructor.
    mv_mode = iv_mode.
  ENDMETHOD.

  METHOD on_link_click.

    DATA: lv_vbeln TYPE vbeln.

    FIELD-SYMBOLS: <fs_del> TYPE ty_delivery,
                   <fs_ord> TYPE ty_order,
                   <fs_bil> TYPE ty_billing,
                   <fs_nst> TYPE ty_nast_check.

    CASE mv_mode.

      WHEN 'D'.  " Delivery
        CASE column.
          WHEN 'VBELN'.
            READ TABLE gt_delivery ASSIGNING <fs_del> INDEX row.
            CHECK sy-subrc = 0.
            lv_vbeln = <fs_del>-vbeln.
            SET PARAMETER ID 'VL' FIELD lv_vbeln.
            CALL TRANSACTION 'VL03N' AND SKIP FIRST SCREEN.
          WHEN 'VGBEL'.
            READ TABLE gt_delivery ASSIGNING <fs_del> INDEX row.
            CHECK sy-subrc = 0.
            lv_vbeln = <fs_del>-vgbel.
            SET PARAMETER ID 'AUN' FIELD lv_vbeln.
            CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN.
        ENDCASE.

      WHEN 'O'.  " Order
        IF column = 'VBELN'.
          READ TABLE gt_order ASSIGNING <fs_ord> INDEX row.
          CHECK sy-subrc = 0.
          lv_vbeln = <fs_ord>-vbeln.
          SET PARAMETER ID 'AUN' FIELD lv_vbeln.
          CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN.
        ENDIF.

      WHEN 'B'.  " Billing
        IF column = 'VBELN'.
          READ TABLE gt_billing ASSIGNING <fs_bil> INDEX row.
          CHECK sy-subrc = 0.
          lv_vbeln = <fs_bil>-vbeln.
          SET PARAMETER ID 'VF' FIELD lv_vbeln.
          CALL TRANSACTION 'VF03' AND SKIP FIRST SCREEN.
        ENDIF.

      WHEN 'N'.  " NAST check
        IF column = 'VBELN'.
          READ TABLE gt_nast_check ASSIGNING <fs_nst> INDEX row.
          CHECK sy-subrc = 0.
          lv_vbeln = <fs_nst>-vbeln.
          SET PARAMETER ID 'VF' FIELD lv_vbeln.
          CALL TRANSACTION 'VF03' AND SKIP FIRST SCREEN.
        ENDIF.

    ENDCASE.

  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Form SELECT_DELIVERIES
*&---------------------------------------------------------------------*
*& Selektiert Lieferungen, die noch nicht (vollstaendig) fakturiert sind.
*& VBUP-FKSTA: A = Nicht fakturiert, B = Teilweise fakturiert
*&---------------------------------------------------------------------*
FORM select_deliveries.

  SELECT delivery~vbeln    item~posnr
         delivery~lfart    delivery~erdat
         delivery~lfdat    delivery~wadat_ist
         delivery~kunnr
         item~matnr        item~arktx
         item~lfimg        item~vrkme
         item~netwr
         item~vgbel        item~vgpos
         status~fksta
    INTO CORRESPONDING FIELDS OF TABLE gt_delivery
    FROM likp AS delivery
    INNER JOIN lips AS item   ON item~vbeln    = delivery~vbeln
    INNER JOIN vbup AS status ON status~vbeln   = item~vbeln
                              AND status~posnr  = item~posnr
    WHERE delivery~vkorg IN s_vkorg
      AND delivery~lfart IN s_lfart
      AND delivery~lfdat IN s_lfdat
      AND delivery~kunnr IN s_kunnr
      AND ( status~fksta = gc_fksta_open
         OR status~fksta = gc_fksta_partial )
      AND item~lfimg > 0.

  CHECK gt_delivery IS NOT INITIAL.

  " Set traffic light and status text
  FIELD-SYMBOLS: <fs_del> TYPE ty_delivery.

  LOOP AT gt_delivery ASSIGNING <fs_del>.
    CASE <fs_del>-fksta.
      WHEN gc_fksta_open.
        <fs_del>-fksta_txt = 'Nicht fakturiert'.
        IF <fs_del>-wadat_ist IS NOT INITIAL.
          " Warenausgang gebucht aber nicht fakturiert -> Rot
          <fs_del>-ampel = gc_ampel_red.
        ELSE.
          " Warenausgang noch nicht gebucht -> Gelb
          <fs_del>-ampel = gc_ampel_yellow.
        ENDIF.
      WHEN gc_fksta_partial.
        <fs_del>-fksta_txt = 'Teilw. fakturiert'.
        <fs_del>-ampel = gc_ampel_yellow.
    ENDCASE.
  ENDLOOP.

  SORT gt_delivery BY kunnr vbeln posnr.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SELECT_ORDERS
*&---------------------------------------------------------------------*
*& Selektiert Streckenauftraege (Positionstyp TAS/YKPS), die
*& auftragsbezogen fakturiert werden koennen und zu denen eine
*& belieferte Streckenbestellung existiert (WE ueber EKBE geprueft).
*& VBUP-FKSTA: A = Nicht fakturiert, B = Teilweise fakturiert
*&---------------------------------------------------------------------*
FORM select_orders.

  TYPES: BEGIN OF lty_pr_link,
           vbeln TYPE vbeln,
           posnr TYPE posnr,
           banfn TYPE banfn,
           bnfpo TYPE bnfpo,
         END OF lty_pr_link.

  TYPES: BEGIN OF lty_po_item,
           banfn TYPE banfn,
           bnfpo TYPE bnfpo,
           ebeln TYPE ebeln,
           ebelp TYPE ebelp,
         END OF lty_po_item.

  TYPES: BEGIN OF lty_gr_key,
           ebeln TYPE ebeln,
           ebelp TYPE ebelp,
         END OF lty_gr_key.

  TYPES: BEGIN OF lty_order_key,
           vbeln TYPE vbeln,
           posnr TYPE posnr,
         END OF lty_order_key.

  DATA: lt_pr_links  TYPE STANDARD TABLE OF lty_pr_link,
        lt_po_items  TYPE STANDARD TABLE OF lty_po_item,
        lt_gr_exists TYPE STANDARD TABLE OF lty_gr_key,
        lt_delivered_orders TYPE HASHED TABLE OF lty_order_key
                            WITH UNIQUE KEY vbeln posnr,
        ls_key TYPE lty_order_key.

  FIELD-SYMBOLS: <fs_ord> TYPE ty_order,
                 <fs_po>  TYPE lty_po_item,
                 <fs_pr>  TYPE lty_pr_link.

  SELECT header~vbeln   item~posnr
         header~audat   header~auart   header~kunnr
         item~matnr     item~arktx     item~kwmeng
         item~vrkme     item~netwr     header~waerk
         header~vkgrp   item~fkrel     status~fksta
    INTO CORRESPONDING FIELDS OF TABLE gt_order
    FROM vbak AS header
    INNER JOIN vbap AS item   ON item~vbeln    = header~vbeln
    INNER JOIN vbup AS status ON status~vbeln   = item~vbeln
                              AND status~posnr  = item~posnr
    WHERE header~vkorg IN s_vkorg
      AND header~vtweg IN s_vtweg
      AND header~spart IN s_spart
      AND header~audat IN s_audat
      AND header~kunnr IN s_kunnr
      AND ( item~pstyv = gc_pstyv_tas
         OR item~pstyv = gc_pstyv_ykps )
      AND item~fkrel   <> space
      AND item~fkrel   <> gc_fkrel_delivery
      AND ( status~fksta = gc_fksta_open
         OR status~fksta = gc_fksta_partial )
      AND item~abgru = space.

  CHECK gt_order IS NOT INITIAL.

  " Nur Positionen mit belieferter Streckenbestellung behalten
  " Kette: Auftrag (VBAP) -> BANF (EBKN) -> Bestellung (EKPO) -> WE (EKBE)

  " 1. EBKN: Bestellanforderungen zu den Auftragspositionen
  SELECT vbeln vbelp AS posnr banfn bnfpo
    INTO CORRESPONDING FIELDS OF TABLE lt_pr_links
    FROM ebkn
    FOR ALL ENTRIES IN gt_order
    WHERE vbeln = gt_order-vbeln
      AND vbelp = gt_order-posnr.

  IF lt_pr_links IS INITIAL.
    CLEAR gt_order.
    RETURN.
  ENDIF.

  " 2. EKPO: Bestellpositionen zu den BANFen (nicht geloescht)
  SELECT banfn bnfpo ebeln ebelp
    INTO CORRESPONDING FIELDS OF TABLE lt_po_items
    FROM ekpo
    FOR ALL ENTRIES IN lt_pr_links
    WHERE banfn = lt_pr_links-banfn
      AND bnfpo = lt_pr_links-bnfpo
      AND loekz = space.

  IF lt_po_items IS INITIAL.
    CLEAR gt_order.
    RETURN.
  ENDIF.

  " 3. EKBE: Wareneingaenge pruefen
  SELECT ebeln ebelp
    INTO TABLE lt_gr_exists
    FROM ekbe
    FOR ALL ENTRIES IN lt_po_items
    WHERE ebeln = lt_po_items-ebeln
      AND ebelp = lt_po_items-ebelp
      AND bewtp = gc_bewtp_gr.

  SORT lt_gr_exists BY ebeln ebelp.
  DELETE ADJACENT DUPLICATES FROM lt_gr_exists COMPARING ebeln ebelp.

  IF lt_gr_exists IS INITIAL.
    CLEAR gt_order.
    RETURN.
  ENDIF.

  " 4. Rueckwaerts-Verknuepfung: PO mit WE -> BANF -> Auftrag
  LOOP AT lt_po_items ASSIGNING <fs_po>.
    READ TABLE lt_gr_exists WITH KEY ebeln = <fs_po>-ebeln
                                     ebelp = <fs_po>-ebelp
                            TRANSPORTING NO FIELDS
                            BINARY SEARCH.
    CHECK sy-subrc = 0.
    LOOP AT lt_pr_links ASSIGNING <fs_pr>
      WHERE banfn = <fs_po>-banfn
        AND bnfpo = <fs_po>-bnfpo.
      ls_key-vbeln = <fs_pr>-vbeln.
      ls_key-posnr = <fs_pr>-posnr.
      INSERT ls_key INTO TABLE lt_delivered_orders.
    ENDLOOP.
  ENDLOOP.

  IF lt_delivered_orders IS INITIAL.
    CLEAR gt_order.
    RETURN.
  ENDIF.

  " 5. gt_order filtern: nur belieferte Positionen behalten
  LOOP AT gt_order ASSIGNING <fs_ord>.
    ls_key-vbeln = <fs_ord>-vbeln.
    ls_key-posnr = <fs_ord>-posnr.
    READ TABLE lt_delivered_orders WITH KEY vbeln = ls_key-vbeln
                                           posnr = ls_key-posnr
                                  TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      DELETE gt_order.
    ENDIF.
  ENDLOOP.

  CHECK gt_order IS NOT INITIAL.

  " Set traffic light and status text
  LOOP AT gt_order ASSIGNING <fs_ord>.
    CASE <fs_ord>-fksta.
      WHEN gc_fksta_open.
        <fs_ord>-fksta_txt = 'Nicht fakturiert'.
        <fs_ord>-ampel = gc_ampel_yellow.
      WHEN gc_fksta_partial.
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
*& VBRK-SFAKN = space -> kein Storno-Beleg (Stornobelege haben SFAKN gefuellt)
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
      AND fkart IN s_fkart
      AND rfbsk <> gc_rfbsk_posted
      AND fksto <> abap_true
      AND sfakn = space.

  CHECK gt_billing IS NOT INITIAL.

  " Set traffic light and status text
  FIELD-SYMBOLS: <fs_bil> TYPE ty_billing.

  LOOP AT gt_billing ASSIGNING <fs_bil>.
    CASE <fs_bil>-rfbsk.
      WHEN gc_rfbsk_open.
        <fs_bil>-rfbsk_txt = 'Nicht uebertragen'.
        <fs_bil>-ampel = gc_ampel_yellow.
      WHEN gc_rfbsk_waiting.
        <fs_bil>-rfbsk_txt = 'Nicht uebertragen'.
        <fs_bil>-ampel = gc_ampel_yellow.
      WHEN gc_rfbsk_error.
        <fs_bil>-rfbsk_txt = 'Fehlerhaft'.
        <fs_bil>-ampel = gc_ampel_red.
    ENDCASE.
  ENDLOOP.

  SORT gt_billing BY bukrs vbeln.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SELECT_NAST_CHECK
*&---------------------------------------------------------------------*
*& Selektiert Fakturen ohne Nachricht oder mit unverarbeiteter/
*& fehlerhafter Nachricht (NAST).
*& KAPPL = 'V3' (Faktura), VSTAT: 0=nicht verarbeitet, 1=OK, 2=Fehler
*&---------------------------------------------------------------------*
FORM select_nast_check.

  TYPES: BEGIN OF ty_vbrk_sel,
           vbeln TYPE vbeln,
           fkdat TYPE fkdat,
           fkart TYPE fkart,
           bukrs TYPE bukrs,
           kunag TYPE kunag,
           netwr TYPE netwr,
           waerk TYPE waerk,
         END OF ty_vbrk_sel,
         BEGIN OF ty_nast_raw,
           objky TYPE nast-objky,
           kschl TYPE kschl,
           vstat TYPE c LENGTH 1,
         END OF ty_nast_raw,
         BEGIN OF ty_objky,
           objky TYPE nast-objky,
         END OF ty_objky.

  DATA: lt_vbrk     TYPE STANDARD TABLE OF ty_vbrk_sel,
        lt_objkeys  TYPE STANDARD TABLE OF ty_objky,
        lt_nast     TYPE STANDARD TABLE OF ty_nast_raw,
        ls_nast     TYPE ty_nast_raw,
        lv_has_good TYPE abap_bool.

  FIELD-SYMBOLS: <fs_vbrk>  TYPE ty_vbrk_sel,
                 <fs_nast>  TYPE ty_nast_raw.

  " Selektiere alle relevanten Fakturen
  SELECT vbeln fkdat fkart bukrs kunag netwr waerk
    INTO CORRESPONDING FIELDS OF TABLE lt_vbrk
    FROM vbrk
    WHERE vkorg IN s_vkorg
      AND vtweg IN s_vtweg
      AND spart IN s_spart
      AND fkdat IN s_fkdat
      AND kunag IN s_kunnr
      AND bukrs IN s_bukrs
      AND fkart IN s_fkart
      AND fksto <> abap_true
      AND sfakn = space
      AND netwr > 0.

  CHECK lt_vbrk IS NOT INITIAL.

  " Hilfstabelle mit OBJKY-Typ aufbauen (NAST-OBJKY ist c70, VBELN ist c10)
  LOOP AT lt_vbrk ASSIGNING <fs_vbrk>.
    APPEND INITIAL LINE TO lt_objkeys ASSIGNING FIELD-SYMBOL(<objkey>).
    <objkey>-objky = <fs_vbrk>-vbeln.
  ENDLOOP.

  " NAST-Eintraege fuer diese Fakturen lesen
  SELECT objky kschl vstat
    INTO CORRESPONDING FIELDS OF TABLE lt_nast
    FROM nast
    FOR ALL ENTRIES IN lt_objkeys
    WHERE objky = lt_objkeys-objky
      AND kappl = gc_kappl_billing.

  SORT lt_nast BY objky.

  " Fakturen filtern: nur solche ohne Nachricht oder mit Problem
  DATA: ls_result TYPE ty_nast_check.

  LOOP AT lt_vbrk ASSIGNING <fs_vbrk>.
    CLEAR ls_result.
    MOVE-CORRESPONDING <fs_vbrk> TO ls_result.

    " Pruefe ob NAST-Eintraege fuer diese Faktura existieren
    READ TABLE lt_nast TRANSPORTING NO FIELDS
      WITH KEY objky = <fs_vbrk>-vbeln
      BINARY SEARCH.

    IF sy-subrc <> 0.
      ls_result-ampel     = gc_ampel_red.
      ls_result-vstat     = gc_vstat_initial.
      ls_result-vstat_txt = 'Keine Nachricht'.
      APPEND ls_result TO gt_nast_check.
      CONTINUE.
    ENDIF.

    " Pruefe alle NAST-Eintraege dieser Faktura
    lv_has_good = abap_false.
    CLEAR ls_nast.

    LOOP AT lt_nast ASSIGNING <fs_nast>
      WHERE objky = <fs_vbrk>-vbeln.
      IF <fs_nast>-vstat = gc_vstat_ok.
        lv_has_good = abap_true.
        EXIT.
      ENDIF.
      ls_nast = <fs_nast>.
    ENDLOOP.

    IF lv_has_good = abap_false.
      ls_result-kschl = ls_nast-kschl.
      ls_result-vstat = ls_nast-vstat.
      CASE ls_nast-vstat.
        WHEN gc_vstat_initial.
          ls_result-ampel     = gc_ampel_yellow.
          ls_result-vstat_txt = 'Nicht verarbeitet'.
        WHEN gc_vstat_error.
          ls_result-ampel     = gc_ampel_red.
          ls_result-vstat_txt = 'Fehlerhaft'.
        WHEN OTHERS.
          ls_result-ampel     = gc_ampel_yellow.
          ls_result-vstat_txt = 'Unbekannter Status'.
      ENDCASE.
      APPEND ls_result TO gt_nast_check.
    ENDIF.

  ENDLOOP.

  SORT gt_nast_check BY bukrs vbeln.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form ENRICH_CUSTOMER_NAMES
*&---------------------------------------------------------------------*
*& Liest Kundennamen aus KNA1 fuer alle Ergebnistabellen.
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
                 <fs_bil> TYPE ty_billing,
                 <fs_nst> TYPE ty_nast_check.

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

  LOOP AT gt_nast_check ASSIGNING <fs_nst>.
    APPEND <fs_nst>-kunag TO lt_kunnr.
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

  " Fill names into nast check table
  LOOP AT gt_nast_check ASSIGNING <fs_nst>.
    READ TABLE lt_kna1 INTO ls_kna1
      WITH KEY kunnr = <fs_nst>-kunag.
    IF sy-subrc = 0.
      <fs_nst>-name1 = ls_kna1-name1.
    ENDIF.
  ENDLOOP.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form ENRICH_VKGRP
*&---------------------------------------------------------------------*
*& Ermittelt die Verkäufergruppe (VKGRP) und deren Bezeichnung (TVGRT)
*& fuer alle Ergebnistabellen.
*&---------------------------------------------------------------------*
FORM enrich_vkgrp.

  TYPES: lty_vkgrp_key TYPE c LENGTH 3.

  TYPES: BEGIN OF lty_vkgrp_map,
           key   TYPE vbeln,
           vkgrp TYPE lty_vkgrp_key,
         END OF lty_vkgrp_map,
         BEGIN OF lty_vkgrp_txt,
           vkgrp TYPE lty_vkgrp_key,
           bezei TYPE char40,
         END OF lty_vkgrp_txt,
         BEGIN OF lty_vbrp_vkgrp,
           vbeln TYPE vbrp-vbeln,
           vkgrp TYPE lty_vkgrp_key,
         END OF lty_vbrp_vkgrp.

  DATA: lt_vkgrp_map  TYPE SORTED TABLE OF lty_vkgrp_map
                      WITH NON-UNIQUE KEY key,
        lt_vkgrp_txt  TYPE SORTED TABLE OF lty_vkgrp_txt
                      WITH UNIQUE KEY vkgrp,
        lt_bill_vkgrp TYPE SORTED TABLE OF lty_vbrp_vkgrp
                      WITH NON-UNIQUE KEY vbeln,
        lt_vkgrp_all  TYPE STANDARD TABLE OF lty_vkgrp_key,
        lt_vgbel      TYPE STANDARD TABLE OF vbeln,
        lt_bill_keys  TYPE STANDARD TABLE OF vbeln,
        ls_map        TYPE lty_vkgrp_map,
        ls_txt        TYPE lty_vkgrp_txt,
        ls_bv         TYPE lty_vbrp_vkgrp.

  FIELD-SYMBOLS: <fs_del> TYPE ty_delivery,
                 <fs_ord> TYPE ty_order,
                 <fs_bil> TYPE ty_billing,
                 <fs_nst> TYPE ty_nast_check.

  " --- A. VKGRP ermitteln pro Beleg ---

  " Aufträge: VKGRP bereits im SELECT (header~vkgrp) -> nur sammeln
  LOOP AT gt_order ASSIGNING <fs_ord>.
    APPEND <fs_ord>-vkgrp TO lt_vkgrp_all.
  ENDLOOP.

  " Lieferungen: VKGRP aus VBAK via vgbel (Auftragsnummer)
  IF gt_delivery IS NOT INITIAL.
    LOOP AT gt_delivery ASSIGNING <fs_del>.
      IF <fs_del>-vgbel IS NOT INITIAL.
        APPEND <fs_del>-vgbel TO lt_vgbel.
      ENDIF.
    ENDLOOP.
    SORT lt_vgbel.
    DELETE ADJACENT DUPLICATES FROM lt_vgbel.
    IF lt_vgbel IS NOT INITIAL.
      SELECT vbeln vkgrp
        INTO TABLE lt_vkgrp_map
        FROM vbak
        FOR ALL ENTRIES IN lt_vgbel
        WHERE vbeln = lt_vgbel-table_line.
      LOOP AT gt_delivery ASSIGNING <fs_del>.
        READ TABLE lt_vkgrp_map INTO ls_map
          WITH KEY key = <fs_del>-vgbel.
        IF sy-subrc = 0.
          <fs_del>-vkgrp = ls_map-vkgrp.
          APPEND ls_map-vkgrp TO lt_vkgrp_all.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

  " Fakturen + NAST: VKGRP aus VBAK via VBRP-AUBEL (JOIN)
  LOOP AT gt_billing ASSIGNING <fs_bil>.
    APPEND <fs_bil>-vbeln TO lt_bill_keys.
  ENDLOOP.
  LOOP AT gt_nast_check ASSIGNING <fs_nst>.
    APPEND <fs_nst>-vbeln TO lt_bill_keys.
  ENDLOOP.
  SORT lt_bill_keys.
  DELETE ADJACENT DUPLICATES FROM lt_bill_keys.

  IF lt_bill_keys IS NOT INITIAL.
    SELECT item~vbeln header~vkgrp
      INTO CORRESPONDING FIELDS OF TABLE lt_bill_vkgrp
      FROM vbrp AS item
      INNER JOIN vbak AS header ON header~vbeln = item~aubel
      FOR ALL ENTRIES IN lt_bill_keys
      WHERE item~vbeln = lt_bill_keys-table_line.

    LOOP AT gt_billing ASSIGNING <fs_bil>.
      READ TABLE lt_bill_vkgrp INTO ls_bv
        WITH KEY vbeln = <fs_bil>-vbeln.
      IF sy-subrc = 0.
        <fs_bil>-vkgrp = ls_bv-vkgrp.
        APPEND ls_bv-vkgrp TO lt_vkgrp_all.
      ENDIF.
    ENDLOOP.

    LOOP AT gt_nast_check ASSIGNING <fs_nst>.
      READ TABLE lt_bill_vkgrp INTO ls_bv
        WITH KEY vbeln = <fs_nst>-vbeln.
      IF sy-subrc = 0.
        <fs_nst>-vkgrp = ls_bv-vkgrp.
        APPEND ls_bv-vkgrp TO lt_vkgrp_all.
      ENDIF.
    ENDLOOP.
  ENDIF.

  " --- B. VKGRP-Bezeichnung aus TVGRT ---
  SORT lt_vkgrp_all.
  DELETE ADJACENT DUPLICATES FROM lt_vkgrp_all.
  DELETE lt_vkgrp_all WHERE table_line IS INITIAL.

  CHECK lt_vkgrp_all IS NOT INITIAL.

  SELECT vkgrp bezei
    INTO TABLE lt_vkgrp_txt
    FROM tvgrt
    FOR ALL ENTRIES IN lt_vkgrp_all
    WHERE spras = sy-langu
      AND vkgrp = lt_vkgrp_all-table_line.

  CHECK lt_vkgrp_txt IS NOT INITIAL.

  " --- C. Text in alle Tabellen eintragen ---
  LOOP AT gt_delivery ASSIGNING <fs_del>.
    READ TABLE lt_vkgrp_txt INTO ls_txt WITH KEY vkgrp = <fs_del>-vkgrp.
    IF sy-subrc = 0. <fs_del>-vkgrp_txt = ls_txt-bezei. ENDIF.
  ENDLOOP.

  LOOP AT gt_order ASSIGNING <fs_ord>.
    READ TABLE lt_vkgrp_txt INTO ls_txt WITH KEY vkgrp = <fs_ord>-vkgrp.
    IF sy-subrc = 0. <fs_ord>-vkgrp_txt = ls_txt-bezei. ENDIF.
  ENDLOOP.

  LOOP AT gt_billing ASSIGNING <fs_bil>.
    READ TABLE lt_vkgrp_txt INTO ls_txt WITH KEY vkgrp = <fs_bil>-vkgrp.
    IF sy-subrc = 0. <fs_bil>-vkgrp_txt = ls_txt-bezei. ENDIF.
  ENDLOOP.

  LOOP AT gt_nast_check ASSIGNING <fs_nst>.
    READ TABLE lt_vkgrp_txt INTO ls_txt WITH KEY vkgrp = <fs_nst>-vkgrp.
    IF sy-subrc = 0. <fs_nst>-vkgrp_txt = ls_txt-bezei. ENDIF.
  ENDLOOP.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form DISPLAY_RESULTS
*&---------------------------------------------------------------------*
*& Zeigt die Ergebnisse als ALV mit CL_SALV_TABLE an.
*& Je nach Radiobutton wird nur eine Tabelle angezeigt.
*&---------------------------------------------------------------------*
FORM display_results.

  DATA: lo_salv    TYPE REF TO cl_salv_table,
        lo_events  TYPE REF TO cl_salv_events_table,
        lo_handler TYPE REF TO lcl_alv_handler,
        lo_display TYPE REF TO cl_salv_display_settings,
        lo_columns TYPE REF TO cl_salv_columns_table,
        lo_funcs   TYPE REF TO cl_salv_functions_list,
        lx_msg     TYPE REF TO cx_salv_msg,
        lv_title   TYPE lvc_title,
        lv_mode    TYPE c LENGTH 1.

  TRY.
      CASE abap_true.

        WHEN p_deliv.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_salv
            CHANGING  t_table      = gt_delivery ).
          lv_title = 'Nicht fakturierte Lieferungen'.
          lv_mode  = 'D'.
          PERFORM set_columns_delivery USING lo_salv.

        WHEN p_order.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_salv
            CHANGING  t_table      = gt_order ).
          lv_title = 'Auftragsbezogen fakturierbare Auftraege'.
          lv_mode  = 'O'.
          PERFORM set_columns_order USING lo_salv.

        WHEN p_billi.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_salv
            CHANGING  t_table      = gt_billing ).
          lv_title = 'Fakturen - nicht in Buchhaltung gebucht'.
          lv_mode  = 'B'.
          PERFORM set_columns_billing USING lo_salv.

        WHEN p_nast.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_salv
            CHANGING  t_table      = gt_nast_check ).
          lv_title = 'Rechnungen ohne / mit fehlerhafter Nachricht'.
          lv_mode  = 'N'.
          PERFORM set_columns_nast USING lo_salv.

      ENDCASE.

    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  " Display settings
  lo_display = lo_salv->get_display_settings( ).
  lo_display->set_list_header( lv_title ).
  lo_display->set_striped_pattern( abap_true ).

  " Enable ALV standard functions (sort, filter, export, etc.)
  lo_funcs = lo_salv->get_functions( ).
  lo_funcs->set_all( abap_true ).

  " Register event handler for hotspot navigation
  CREATE OBJECT lo_handler
    EXPORTING iv_mode = lv_mode.

  lo_events = lo_salv->get_event( ).
  SET HANDLER lo_handler->on_link_click FOR lo_events.

  " Optimize column widths
  lo_columns = lo_salv->get_columns( ).
  lo_columns->set_optimize( abap_true ).

  lo_salv->display( ).

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SET_COLUMNS_DELIVERY
*&---------------------------------------------------------------------*
*& Spalteneinstellungen fuer Lieferungs-ALV
*&---------------------------------------------------------------------*
FORM set_columns_delivery USING io_salv TYPE REF TO cl_salv_table.

  DATA: lo_columns TYPE REF TO cl_salv_columns_table,
        lo_column  TYPE REF TO cl_salv_column_table,
        lo_aggrs   TYPE REF TO cl_salv_aggregations.

  lo_columns = io_salv->get_columns( ).
  lo_aggrs   = io_salv->get_aggregations( ).

  TRY.
      " Traffic light column
      lo_column ?= lo_columns->get_column( 'AMPEL' ).
      lo_column->set_short_text( 'Status' ).
      lo_columns->set_exception_column( 'AMPEL' ).

      lo_column ?= lo_columns->get_column( 'VBELN' ).
      lo_column->set_short_text( 'Lieferung' ).
      lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_column ?= lo_columns->get_column( 'POSNR' ).
      lo_column->set_short_text( 'Position' ).

      lo_column ?= lo_columns->get_column( 'LFART' ).
      lo_column->set_short_text( 'LiefArt' ).
      lo_column->set_medium_text( 'Lieferart' ).

      lo_column ?= lo_columns->get_column( 'ERDAT' ).
      lo_column->set_short_text( 'Angelegt' ).

      lo_column ?= lo_columns->get_column( 'LFDAT' ).
      lo_column->set_short_text( 'Lieferdat' ).

      lo_column ?= lo_columns->get_column( 'WADAT_IST' ).
      lo_column->set_short_text( 'WA-Datum' ).

      lo_column ?= lo_columns->get_column( 'KUNNR' ).
      lo_column->set_short_text( 'Kunde' ).

      lo_column ?= lo_columns->get_column( 'NAME1' ).
      lo_column->set_short_text( 'Kundenname' ).

      lo_column ?= lo_columns->get_column( 'MATNR' ).
      lo_column->set_short_text( 'Material' ).

      lo_column ?= lo_columns->get_column( 'ARKTX' ).
      lo_column->set_short_text( 'Bezeichng' ).

      lo_column ?= lo_columns->get_column( 'LFIMG' ).
      lo_column->set_short_text( 'Liefermng' ).

      lo_column ?= lo_columns->get_column( 'VRKME' ).
      lo_column->set_short_text( 'ME' ).

      lo_column ?= lo_columns->get_column( 'NETWR' ).
      lo_column->set_short_text( 'Nettowert' ).

      lo_column ?= lo_columns->get_column( 'VGBEL' ).
      lo_column->set_short_text( 'Auftrag' ).
      lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_column ?= lo_columns->get_column( 'VGPOS' ).
      lo_column->set_short_text( 'Auftr.Pos' ).

      lo_column ?= lo_columns->get_column( 'FKSTA' ).
      lo_column->set_technical( abap_true ).

      lo_column ?= lo_columns->get_column( 'FKSTA_TXT' ).
      lo_column->set_short_text( 'FaktStat' ).
      lo_column->set_medium_text( 'Fakturastatus' ).

      lo_column ?= lo_columns->get_column( 'VKGRP' ).
      lo_column->set_short_text( 'VkGrp' ).

      lo_column ?= lo_columns->get_column( 'VKGRP_TXT' ).
      lo_column->set_short_text( 'VkGrp Bez' ).
      lo_column->set_medium_text( 'Verkauefergruppe' ).

      lo_aggrs->add_aggregation( columnname = 'NETWR' aggregation = if_salv_c_aggregation=>total ).

    CATCH cx_salv_not_found cx_salv_data_error cx_salv_existing. "#EC NO_HANDLER
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SET_COLUMNS_ORDER
*&---------------------------------------------------------------------*
*& Spalteneinstellungen fuer Auftrags-ALV
*&---------------------------------------------------------------------*
FORM set_columns_order USING io_salv TYPE REF TO cl_salv_table.

  DATA: lo_columns TYPE REF TO cl_salv_columns_table,
        lo_column  TYPE REF TO cl_salv_column_table,
        lo_aggrs   TYPE REF TO cl_salv_aggregations.

  lo_columns = io_salv->get_columns( ).
  lo_aggrs   = io_salv->get_aggregations( ).

  TRY.
      lo_column ?= lo_columns->get_column( 'AMPEL' ).
      lo_column->set_short_text( 'Status' ).
      lo_columns->set_exception_column( 'AMPEL' ).

      lo_column ?= lo_columns->get_column( 'VBELN' ).
      lo_column->set_short_text( 'Auftrag' ).
      lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_column ?= lo_columns->get_column( 'POSNR' ).
      lo_column->set_short_text( 'Position' ).

      lo_column ?= lo_columns->get_column( 'AUDAT' ).
      lo_column->set_short_text( 'Auftr.Dat' ).

      lo_column ?= lo_columns->get_column( 'AUART' ).
      lo_column->set_short_text( 'Auftr.Art' ).

      lo_column ?= lo_columns->get_column( 'KUNNR' ).
      lo_column->set_short_text( 'Kunde' ).

      lo_column ?= lo_columns->get_column( 'NAME1' ).
      lo_column->set_short_text( 'Kundenname' ).

      lo_column ?= lo_columns->get_column( 'MATNR' ).
      lo_column->set_short_text( 'Material' ).

      lo_column ?= lo_columns->get_column( 'ARKTX' ).
      lo_column->set_short_text( 'Bezeichng' ).

      lo_column ?= lo_columns->get_column( 'KWMENG' ).
      lo_column->set_short_text( 'AuftrMeng' ).

      lo_column ?= lo_columns->get_column( 'VRKME' ).
      lo_column->set_short_text( 'ME' ).

      lo_column ?= lo_columns->get_column( 'NETWR' ).
      lo_column->set_short_text( 'Nettowert' ).

      lo_column ?= lo_columns->get_column( 'WAERK' ).
      lo_column->set_short_text( 'Waehr.' ).

      lo_column ?= lo_columns->get_column( 'FKREL' ).
      lo_column->set_technical( abap_true ).

      lo_column ?= lo_columns->get_column( 'FKSTA' ).
      lo_column->set_technical( abap_true ).

      lo_column ?= lo_columns->get_column( 'FKSTA_TXT' ).
      lo_column->set_short_text( 'FaktStat' ).
      lo_column->set_medium_text( 'Fakturastatus' ).

      lo_column ?= lo_columns->get_column( 'VKGRP' ).
      lo_column->set_short_text( 'VkGrp' ).

      lo_column ?= lo_columns->get_column( 'VKGRP_TXT' ).
      lo_column->set_short_text( 'VkGrp Bez' ).
      lo_column->set_medium_text( 'Verkauefergruppe' ).

      lo_aggrs->add_aggregation( columnname = 'KWMENG' aggregation = if_salv_c_aggregation=>total ).
      lo_aggrs->add_aggregation( columnname = 'NETWR'  aggregation = if_salv_c_aggregation=>total ).

    CATCH cx_salv_not_found cx_salv_data_error cx_salv_existing. "#EC NO_HANDLER
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SET_COLUMNS_BILLING
*&---------------------------------------------------------------------*
*& Spalteneinstellungen fuer Faktura-ALV
*&---------------------------------------------------------------------*
FORM set_columns_billing USING io_salv TYPE REF TO cl_salv_table.

  DATA: lo_columns TYPE REF TO cl_salv_columns_table,
        lo_column  TYPE REF TO cl_salv_column_table,
        lo_aggrs   TYPE REF TO cl_salv_aggregations.

  lo_columns = io_salv->get_columns( ).
  lo_aggrs   = io_salv->get_aggregations( ).

  TRY.
      lo_column ?= lo_columns->get_column( 'AMPEL' ).
      lo_column->set_short_text( 'Status' ).
      lo_columns->set_exception_column( 'AMPEL' ).

      lo_column ?= lo_columns->get_column( 'VBELN' ).
      lo_column->set_short_text( 'Faktura' ).
      lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_column ?= lo_columns->get_column( 'FKDAT' ).
      lo_column->set_short_text( 'Fakt.Dat' ).

      lo_column ?= lo_columns->get_column( 'FKART' ).
      lo_column->set_short_text( 'Fakt.Art' ).

      lo_column ?= lo_columns->get_column( 'BUKRS' ).
      lo_column->set_short_text( 'BuKrs' ).

      lo_column ?= lo_columns->get_column( 'KUNAG' ).
      lo_column->set_short_text( 'Auftrgeb' ).

      lo_column ?= lo_columns->get_column( 'NAME1' ).
      lo_column->set_short_text( 'Kundenname' ).

      lo_column ?= lo_columns->get_column( 'NETWR' ).
      lo_column->set_short_text( 'Nettowert' ).

      lo_column ?= lo_columns->get_column( 'MWSBK' ).
      lo_column->set_short_text( 'Steuer' ).

      lo_column ?= lo_columns->get_column( 'WAERK' ).
      lo_column->set_short_text( 'Waehr.' ).

      lo_column ?= lo_columns->get_column( 'RFBSK' ).
      lo_column->set_technical( abap_true ).

      lo_column ?= lo_columns->get_column( 'RFBSK_TXT' ).
      lo_column->set_short_text( 'BuchStat' ).
      lo_column->set_medium_text( 'Buchungsstatus' ).

      lo_column ?= lo_columns->get_column( 'ERDAT' ).
      lo_column->set_short_text( 'Angelegt' ).

      lo_column ?= lo_columns->get_column( 'ERNAM' ).
      lo_column->set_short_text( 'Ersteller' ).

      lo_column ?= lo_columns->get_column( 'VKGRP' ).
      lo_column->set_short_text( 'VkGrp' ).

      lo_column ?= lo_columns->get_column( 'VKGRP_TXT' ).
      lo_column->set_short_text( 'VkGrp Bez' ).
      lo_column->set_medium_text( 'Verkauefergruppe' ).

      lo_aggrs->add_aggregation( columnname = 'NETWR' aggregation = if_salv_c_aggregation=>total ).
      lo_aggrs->add_aggregation( columnname = 'MWSBK' aggregation = if_salv_c_aggregation=>total ).

    CATCH cx_salv_not_found cx_salv_data_error cx_salv_existing. "#EC NO_HANDLER
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form SET_COLUMNS_NAST
*&---------------------------------------------------------------------*
*& Spalteneinstellungen fuer NAST-Pruefungs-ALV
*&---------------------------------------------------------------------*
FORM set_columns_nast USING io_salv TYPE REF TO cl_salv_table.

  DATA: lo_columns TYPE REF TO cl_salv_columns_table,
        lo_column  TYPE REF TO cl_salv_column_table,
        lo_aggrs   TYPE REF TO cl_salv_aggregations.

  lo_columns = io_salv->get_columns( ).
  lo_aggrs   = io_salv->get_aggregations( ).

  TRY.
      lo_column ?= lo_columns->get_column( 'AMPEL' ).
      lo_column->set_short_text( 'Status' ).
      lo_columns->set_exception_column( 'AMPEL' ).

      lo_column ?= lo_columns->get_column( 'VBELN' ).
      lo_column->set_short_text( 'Faktura' ).
      lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).

      lo_column ?= lo_columns->get_column( 'FKDAT' ).
      lo_column->set_short_text( 'Fakt.Dat' ).

      lo_column ?= lo_columns->get_column( 'FKART' ).
      lo_column->set_short_text( 'Fakt.Art' ).

      lo_column ?= lo_columns->get_column( 'BUKRS' ).
      lo_column->set_short_text( 'BuKrs' ).

      lo_column ?= lo_columns->get_column( 'KUNAG' ).
      lo_column->set_short_text( 'Auftrgeb' ).

      lo_column ?= lo_columns->get_column( 'NAME1' ).
      lo_column->set_short_text( 'Kundenname' ).

      lo_column ?= lo_columns->get_column( 'NETWR' ).
      lo_column->set_short_text( 'Nettowert' ).

      lo_column ?= lo_columns->get_column( 'WAERK' ).
      lo_column->set_short_text( 'Waehr.' ).

      lo_column ?= lo_columns->get_column( 'VKGRP' ).
      lo_column->set_short_text( 'VkGrp' ).

      lo_column ?= lo_columns->get_column( 'VKGRP_TXT' ).
      lo_column->set_short_text( 'VkGrp Bez' ).
      lo_column->set_medium_text( 'Verkauefergruppe' ).

      lo_column ?= lo_columns->get_column( 'KSCHL' ).
      lo_column->set_short_text( 'NachArt' ).
      lo_column->set_medium_text( 'Nachrichtenart' ).

      lo_column ?= lo_columns->get_column( 'VSTAT' ).
      lo_column->set_technical( abap_true ).

      lo_column ?= lo_columns->get_column( 'VSTAT_TXT' ).
      lo_column->set_short_text( 'NachStat' ).
      lo_column->set_medium_text( 'Nachrichtenstatus' ).

      lo_aggrs->add_aggregation( columnname = 'NETWR' aggregation = if_salv_c_aggregation=>total ).

    CATCH cx_salv_not_found cx_salv_data_error cx_salv_existing. "#EC NO_HANDLER
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form BUILD_CSV_CONTENT
*&---------------------------------------------------------------------*
*& Erzeugt den CSV-Inhalt (Semikolon-getrennt) fuer den aktiven Block.
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
                 <fs_bil> TYPE ty_billing,
                 <fs_nst> TYPE ty_nast_check.

  CLEAR ct_csv.

  CASE abap_true.

    "--- Nicht fakturierte Lieferungen ---
    WHEN p_deliv.
      IF gt_delivery IS NOT INITIAL.
        APPEND 'Nicht fakturierte Lieferungen' TO ct_csv.

        CONCATENATE
          'Lieferung' 'Position' 'Lieferart' 'Angelegt am'
          'Lieferdatum' 'WA-Datum' 'Kunde' 'Kundenname'
          'Material' 'Bezeichnung' 'Liefermenge' 'ME'
          'Nettowert' 'Auftrag' 'Auftr.Pos'
          'Fakturastatus'
          'Verkauefergruppe' 'VkGrp Bezeichnung'
          INTO lv_line SEPARATED BY gc_csv_sep.
        APPEND lv_line TO ct_csv.

        LOOP AT gt_delivery ASSIGNING <fs_del>.
          WRITE <fs_del>-lfimg TO lv_lfimg LEFT-JUSTIFIED.
          WRITE <fs_del>-netwr TO lv_netwr LEFT-JUSTIFIED.
          CONCATENATE
            <fs_del>-vbeln <fs_del>-posnr <fs_del>-lfart <fs_del>-erdat
            <fs_del>-lfdat <fs_del>-wadat_ist <fs_del>-kunnr <fs_del>-name1
            <fs_del>-matnr <fs_del>-arktx lv_lfimg <fs_del>-vrkme
            lv_netwr <fs_del>-vgbel <fs_del>-vgpos
            <fs_del>-fksta_txt
            <fs_del>-vkgrp <fs_del>-vkgrp_txt
            INTO lv_line SEPARATED BY gc_csv_sep.
          APPEND lv_line TO ct_csv.
        ENDLOOP.
      ENDIF.

    "--- Auftragsbezogen fakturierbare Auftraege ---
    WHEN p_order.
      IF gt_order IS NOT INITIAL.
        APPEND 'Auftragsbezogen fakturierbare Auftraege' TO ct_csv.

        CONCATENATE
          'Auftrag' 'Position' 'Auftragsdatum' 'Auftragsart'
          'Kunde' 'Kundenname' 'Material' 'Bezeichnung'
          'Auftragsmenge' 'ME' 'Nettowert' 'Waehrung'
          'Fakturastatus' 'Verkauefergruppe' 'VkGrp Bezeichnung'
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
            <fs_ord>-vkgrp <fs_ord>-vkgrp_txt
            INTO lv_line SEPARATED BY gc_csv_sep.
          APPEND lv_line TO ct_csv.
        ENDLOOP.
      ENDIF.

    "--- Fakturen nicht in Buchhaltung ---
    WHEN p_billi.
      IF gt_billing IS NOT INITIAL.
        APPEND 'Fakturen - nicht in Buchhaltung gebucht' TO ct_csv.

        CONCATENATE
          'Faktura' 'Fakturadatum' 'Fakturaart' 'Buchungskreis'
          'Auftraggeber' 'Kundenname' 'Nettowert' 'Steuerbetrag'
          'Waehrung' 'Buchungsstatus' 'Angelegt am' 'Angelegt von'
          'Verkauefergruppe' 'VkGrp Bezeichnung'
          INTO lv_line SEPARATED BY gc_csv_sep.
        APPEND lv_line TO ct_csv.

        LOOP AT gt_billing ASSIGNING <fs_bil>.
          WRITE <fs_bil>-netwr TO lv_netwr LEFT-JUSTIFIED.
          WRITE <fs_bil>-mwsbk TO lv_mwsbk LEFT-JUSTIFIED.
          CONCATENATE
            <fs_bil>-vbeln <fs_bil>-fkdat <fs_bil>-fkart <fs_bil>-bukrs
            <fs_bil>-kunag <fs_bil>-name1 lv_netwr lv_mwsbk
            <fs_bil>-waerk <fs_bil>-rfbsk_txt <fs_bil>-erdat <fs_bil>-ernam
            <fs_bil>-vkgrp <fs_bil>-vkgrp_txt
            INTO lv_line SEPARATED BY gc_csv_sep.
          APPEND lv_line TO ct_csv.
        ENDLOOP.
      ENDIF.

    "--- Rechnungen ohne / mit fehlerhafter Nachricht ---
    WHEN p_nast.
      IF gt_nast_check IS NOT INITIAL.
        APPEND 'Rechnungen ohne / mit fehlerhafter Nachricht' TO ct_csv.

        CONCATENATE
          'Faktura' 'Fakturadatum' 'Fakturaart' 'Buchungskreis'
          'Auftraggeber' 'Kundenname' 'Nettowert' 'Waehrung'
          'Verkauefergruppe' 'VkGrp Bezeichnung'
          'Nachrichtenart' 'Nachrichtenstatus'
          INTO lv_line SEPARATED BY gc_csv_sep.
        APPEND lv_line TO ct_csv.

        LOOP AT gt_nast_check ASSIGNING <fs_nst>.
          WRITE <fs_nst>-netwr TO lv_netwr LEFT-JUSTIFIED.
          CONCATENATE
            <fs_nst>-vbeln <fs_nst>-fkdat <fs_nst>-fkart <fs_nst>-bukrs
            <fs_nst>-kunag <fs_nst>-name1 lv_netwr <fs_nst>-waerk
            <fs_nst>-vkgrp <fs_nst>-vkgrp_txt
            <fs_nst>-kschl <fs_nst>-vstat_txt
            INTO lv_line SEPARATED BY gc_csv_sep.
          APPEND lv_line TO ct_csv.
        ENDLOOP.
      ENDIF.

  ENDCASE.

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
        lx_root         TYPE REF TO cx_root,
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

  TRY.
      " CSV in einen String zusammenfuehren
      CONCATENATE LINES OF lt_csv
        INTO lv_csv_str
        SEPARATED BY cl_abap_char_utilities=>cr_lf.

      " In UTF-8 xstring konvertieren (mit BOM fuer Excel)
      lo_conv = cl_abap_conv_out_ce=>create( encoding = '4110' ).
      lo_conv->write( data = lv_csv_str ).
      lv_xstr_csv = lo_conv->get_buffer( ).
      lv_xstr = lv_bom.
      CONCATENATE lv_xstr lv_xstr_csv INTO lv_xstr IN BYTE MODE.

      " xstring in SOLIX-Tabelle konvertieren
      lt_solix = cl_bcs_convert=>xstring_to_solix( iv_xstring = lv_xstr ).
      lv_att_size = xstrlen( lv_xstr ).

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

      DESCRIBE TABLE gt_nast_check LINES lv_count.
      WRITE lv_count TO lv_text LEFT-JUSTIFIED.
      CONCATENATE 'Rechnungen ohne Nachricht:' lv_text
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

    CATCH cx_root INTO lx_root.
      lv_error = lx_root->get_text( ).
      MESSAGE s398(00) WITH 'E-Mail-Fehler:' lv_error space space DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.
