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
    EXCEPTIONMSG = EXCEPTIONMSG
  TABLES
    IT_CSV = IT_CSV
  CHANGING
    RETURN = RETURN
  EXCEPTIONS
    SENDEXCEPTIONTOSAPSERVER  = 1
    YOUR_EXCEPTION_NAME_HERE  = 2
    system_failure            = 3 MESSAGE EXCEPTIONMSG
    communication_failure     = 4 MESSAGE EXCEPTIONMSG
    OTHERS                    = 5.

CASE sy-subrc.
  WHEN 0.
    EXCEPTIONMSG = 'ok'.
  WHEN 1 or 2.
    EXCEPTIONMSG = |Exception from workflow: { sy-msgv1 }{ sy-msgv2 }{ sy-msgv3 }{ sy-msgv4 } |.
  WHEN 3 or 4.
  WHEN OTHERS.
    EXCEPTIONMSG = |Error in workflow: { sy-msgv1 }{ sy-msgv2 }{ sy-msgv3 }{ sy-msgv4 } |.
ENDCASE.

ENDFUNCTION.