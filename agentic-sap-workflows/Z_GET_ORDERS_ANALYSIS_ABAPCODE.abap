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

CALL FUNCTION 'Z_GET_ORDERS_ANALYSIS' DESTINATION DEST
  IMPORTING
    ANALYSIS = ANALYSIS
  TABLES
    IT_CSV = IT_CSV
  CHANGING
    RETURN = RETURN
  EXCEPTIONS
    SENDEXCEPTIONTOSAPSERVER  = 1
    system_failure            = 2 MESSAGE EXCEPTIONMSG
    communication_failure     = 3 MESSAGE EXCEPTIONMSG
    OTHERS                    = 4.

CASE sy-subrc.
  WHEN 0.
    EXCEPTIONMSG = 'ok'.
  WHEN 1.
    EXCEPTIONMSG = |Exception from workflow: SENDEXCEPTIONTOSAPSERVER { sy-msgv1 }{ sy-msgv2 }{ sy-msgv3 }{ sy-msgv4 } |.
  WHEN 2 or 3.
  WHEN OTHERS.
    EXCEPTIONMSG = |Error in workflow: { sy-msgv1 }{ sy-msgv2 }{ sy-msgv3 }{ sy-msgv4 } |.
ENDCASE.

ENDFUNCTION.