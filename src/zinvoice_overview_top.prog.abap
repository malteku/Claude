*&---------------------------------------------------------------------*
*& Include /MBSO/ZINVOICE_OVERVIEW_TOP
*&---------------------------------------------------------------------*
*& Globale Definitionen: Typen, Konstanten, globale Daten
*&---------------------------------------------------------------------*

TYPE-POOLS: slis.

*----------------------------------------------------------------------*
* Constants
*----------------------------------------------------------------------*
CONSTANTS:
  gc_ampel_red    TYPE c LENGTH 1 VALUE '1',
  gc_ampel_yellow TYPE c LENGTH 1 VALUE '2',
  gc_ampel_green  TYPE c LENGTH 1 VALUE '3',
  gc_csv_sep      TYPE c LENGTH 1 VALUE ';'.

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
    netwr     TYPE netwr,
    waerk     TYPE waerk,
    mwsbk     TYPE MWSBP,
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
  gv_fkdat TYPE fkdat,
  gv_email TYPE ad_smtpadr.

* Block titles (set in INITIALIZATION)
DATA:
  gv_t_b01 TYPE char40,
  gv_t_b02 TYPE char40,
  gv_t_b03 TYPE char40,
  gv_t_b04 TYPE char40,
  gv_t_b05 TYPE char40.
