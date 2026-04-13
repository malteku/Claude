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

INCLUDE /mbso/zinvoice_overview_top.
INCLUDE /mbso/zinvoice_overview_sel.
INCLUDE /mbso/zinvoice_overview_cl1.

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
