*&---------------------------------------------------------------------*
*& Include /MBSO/ZINVOICE_OVERVIEW_SEL
*&---------------------------------------------------------------------*
*& Selektionsbild, Initialisierung und Selektionspruefungen
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE gv_t_b1b.
  SELECT-OPTIONS:
    s_vkorg FOR gv_vkorg OBLIGATORY,
    s_vtweg FOR gv_vtweg,
    s_spart FOR gv_spart,
    s_bukrs FOR gv_bukrs.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE gv_t_b2b.
  SELECT-OPTIONS:
    s_kunnr FOR gv_kunnr.
SELECTION-SCREEN END OF BLOCK b02.

SELECTION-SCREEN BEGIN OF BLOCK b03 WITH FRAME TITLE gv_t_b3b.
  SELECT-OPTIONS:
    s_lfdat FOR gv_lfdat,
    s_audat FOR gv_audat,
    s_fkdat FOR gv_fkdat.
SELECTION-SCREEN END OF BLOCK b03.

SELECTION-SCREEN BEGIN OF BLOCK b04 WITH FRAME TITLE gv_t_b4b.
  PARAMETERS:
    p_deliv AS CHECKBOX DEFAULT 'X' USER-COMMAND uc1,
    p_order AS CHECKBOX DEFAULT 'X' USER-COMMAND uc2,
    p_billi AS CHECKBOX DEFAULT 'X' USER-COMMAND uc3.
SELECTION-SCREEN END OF BLOCK b04.

SELECTION-SCREEN BEGIN OF BLOCK b05 WITH FRAME TITLE gv_t_b05.
  PARAMETERS:
    p_excel AS CHECKBOX.
  SELECT-OPTIONS:
    s_email FOR gv_email NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b05.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  gv_t_b01 = 'Organisationsdaten'.
  gv_t_b02 = 'Partner'.
  gv_t_b03 = 'Datumseingrenzung'.
  gv_t_b04 = 'Anzeigeoptionen'.
  gv_t_b05 = 'Export / Versand'.

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
  %_p_excel_%_app_%-text = 'Excel-Export (Vordergr.)'.
  %_s_email_%_app_%-text = 'E-Mail-Empfaenger'.

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
