*&---------------------------------------------------------------------*
*& Report ZINVOICE_OVERVIEW
*&---------------------------------------------------------------------*
*& Faktura-Uebersichtsreport
*&
*& Dieser Report zeigt vier Bereiche:
*& 1. Lieferungen, die noch nicht fakturiert wurden
*& 2. Auftraege, die auftragsbezogen fakturiert werden koennen
*& 3. Fakturen, die noch nicht in der Buchhaltung gebucht sind
*& 4. Rechnungen ohne oder mit unverarbeiteter Nachricht (NAST)
*&
*& Verwendete SAP-Tabellen:
*&   LIKP/LIPS - Lieferung (Kopf/Position)
*&   VBAK/VBAP - Kundenauftrag (Kopf/Position)
*&   VBRK      - Faktura (Kopf)
*&   VBUP      - Positionsstatus (ECC) / Kompatibilitaetsview (S/4HANA)
*&   NAST      - Nachrichtenstatus
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

  CASE abap_true.
    WHEN p_deliv.
      PERFORM select_deliveries.
    WHEN p_order.
      PERFORM select_orders.
    WHEN p_billi.
      PERFORM select_billings.
    WHEN p_nast.
      PERFORM select_nast_check.
  ENDCASE.

  " Enrich all tables with customer names in one pass
  PERFORM enrich_customer_names.
  PERFORM enrich_vkgrp.

*----------------------------------------------------------------------*
* END-OF-SELECTION
*----------------------------------------------------------------------*
END-OF-SELECTION.

  IF   gt_delivery   IS INITIAL
   AND gt_order      IS INITIAL
   AND gt_billing    IS INITIAL
   AND gt_nast_check IS INITIAL.
    MESSAGE s398(00) WITH 'Keine Daten zur Selektion gefunden' space space space.
    RETURN.
  ENDIF.

  " E-Mail-Versand (funktioniert auch im Hintergrundjob)
  IF s_email[] IS NOT INITIAL.
    PERFORM send_results_by_email.
  ENDIF.

  " Excel-Export nur im Vordergrund
  IF p_excel = abap_true AND sy-batch IS INITIAL.
    PERFORM export_to_excel.
  ENDIF.

  " ALV-Anzeige nur im Vordergrund
  IF sy-batch IS INITIAL.
    PERFORM display_results.
  ENDIF.
