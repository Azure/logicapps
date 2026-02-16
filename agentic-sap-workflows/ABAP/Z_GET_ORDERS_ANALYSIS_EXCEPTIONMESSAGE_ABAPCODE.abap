FUNCTION Z_GET_ORDERS_ANALYSIS.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(DEST) TYPE  CHAR20 DEFAULT 'YOURDESTINATION'
*"  EXPORTING
*"     VALUE(EXCEPTIONMSG) TYPE  ZCHAR1000
*"     VALUE(ANALYSIS) TYPE  STRING
*"  TABLES
*"      IT_CSV STRUCTURE  ZTY_CSV_LINE
*"  CHANGING
*"     VALUE(RETURN) TYPE  BAPIRET2 OPTIONAL
*"  EXCEPTIONS
*"      SENDEXCEPTIONTOSAPSERVER
*"----------------------------------------------------------------------

* SUBMITs ZCREATE_ONLINEORDER_IDOC for each CSV line, passing parameters.
*-----------------------------------------------------------------------

TRY.
CALL FUNCTION 'Z_GET_ORDERS_ANALYSIS' DESTINATION DEST
  IMPORTING
    ANALYSIS = ANALYSIS
    EXCEPTIONMSG = EXCEPTIONMSG
  TABLES
    IT_CSV = IT_CSV
  CHANGING
    RETURN = RETURN
  EXCEPTIONS
    system_failure            = 1
    communication_failure     = 2.

CATCH
cx_root INTO DATA(lx_any). "Optional for other exceptions

ENDTRY.

IF sy-subrc <> 0.

DATA: lv_text TYPE string.

CALL FUNCTION 'FORMAT_MESSAGE'
    EXPORTING
      id      = sy-msgid
      NO      = sy-msgno
      v1      = sy-msgv1
      v2      = sy-msgv2
      v3      = sy-msgv3
      v4      = sy-msgv4
    IMPORTING
      msg     = EXCEPTIONMSG.

ENDIF.

ENDFUNCTION.