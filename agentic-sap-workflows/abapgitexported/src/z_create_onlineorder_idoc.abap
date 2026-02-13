FUNCTION z_create_onlineorder_idoc.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_DIRECTION) TYPE  CHAR01 DEFAULT 'O'
*"     VALUE(IV_IDOCTYP) TYPE  EDI_IDOCTP DEFAULT 'ZONLINEORDERIDOC'
*"     VALUE(IV_MESTYP) TYPE  EDIDC-MESTYP DEFAULT 'ZONLINEORDER'
*"     VALUE(IV_SEGTP) TYPE  EDIHSEGTYP DEFAULT 'ZONLINEORDER'
*"     VALUE(IV_SNDPRT) TYPE  EDIDC-SNDPRT OPTIONAL
*"     VALUE(IV_SNDPRN) TYPE  EDIDC-SNDPRN OPTIONAL
*"     VALUE(IV_RCVPRT) TYPE  EDIDC-RCVPRT OPTIONAL
*"     VALUE(IV_RCVPRN) TYPE  EDIDC-RCVPRN OPTIONAL
*"     VALUE(IV_RCVPOR) TYPE  EDIDC-RCVPOR OPTIONAL
*"  EXPORTING
*"     VALUE(EV_DOCNUM) TYPE  EDIDC-DOCNUM
*"  TABLES
*"      IT_CSV STRUCTURE  ZTY_CSV_LINE
*"      ET_RETURN STRUCTURE  BAPIRET2
*"      ET_DOCNUMS TYPE  ZTY_DOCNUM_TT
*"----------------------------------------------------------------------

  DATA: ls_ret TYPE bapiret2.

  " --- Validate direction once
  IF iv_direction <> 'I' AND iv_direction <> 'O'.
    CLEAR ls_ret.
    ls_ret-type       = 'E'.
    ls_ret-id         = 'ZORD'.
    ls_ret-number     = '002'.
    ls_ret-message    = 'IV_DIRECTION must be I (inbound) or O (outbound).'.
    ls_ret-message_v1 = 'I'.
    ls_ret-message_v2 = 'O'.
    APPEND ls_ret TO et_return.
    RETURN.
  ENDIF.

  " --- Ensure we have at least one row
  IF it_csv[] IS INITIAL.
    CLEAR ls_ret.
    ls_ret-type    = 'E'.
    ls_ret-id      = 'ZORD'.
    ls_ret-number  = '003'.
    ls_ret-message = 'IT_CSV must contain at least one line.'.
    APPEND ls_ret TO et_return.
    RETURN.
  ENDIF.

  " ====================================================================
  " Main loop: each IT_CSV-LINE is one CSV record
  " ====================================================================
  DATA: lv_idx TYPE i VALUE 0.

  LOOP AT it_csv INTO DATA(wa_csv).
    lv_idx = lv_idx + 1.

    DATA(lv_csv) = CONV string( wa_csv-line ). " ZTY_CSV_LINE-LINE is CHAR2048

    " --- Parse CSV into 14 tokens (quotes, commas-in-quotes, "" escape)
    TYPES: string_tt TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA: lt_tokens TYPE string_tt,
          lv_len TYPE i, lv_pos TYPE i, lv_inq TYPE c LENGTH 1,
          lv_c   TYPE c LENGTH 1, lv_buf TYPE string.

    CLEAR: lt_tokens, lv_buf, lv_inq.
    lv_len = strlen( lv_csv ).
    lv_pos = 0.

    WHILE lv_pos < lv_len.
      lv_c = lv_csv+lv_pos(1).
      IF lv_c = '"'.
        IF lv_inq IS INITIAL.
          lv_inq = 'X'.
        ELSE.
          DATA(lv_next) = lv_pos + 1.
          IF lv_next < lv_len AND lv_csv+lv_next(1) = '"'.
            CONCATENATE lv_buf '"' INTO lv_buf.
            lv_pos = lv_pos + 1.
          ELSE.
            CLEAR lv_inq.
          ENDIF.
        ENDIF.
      ELSEIF lv_c = ',' AND lv_inq IS INITIAL.
        APPEND lv_buf TO lt_tokens.
        CLEAR lv_buf.
      ELSE.
        CONCATENATE lv_buf lv_c INTO lv_buf.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.
    APPEND lv_buf TO lt_tokens.

    IF lines( lt_tokens ) <> 14.
      CLEAR ls_ret.
      ls_ret-type    = 'E'.
      ls_ret-id      = 'ZORD'.
      ls_ret-number  = '032'.
      ls_ret-message = |Row { lv_idx }: CSV must contain exactly 14 comma-separated values.| .
      APPEND ls_ret TO et_return.
      CONTINUE.
    ENDIF.

    " --- Map tokens
    DATA: lv_order_id           TYPE string,
          lv_order_date_text    TYPE string,
          lv_customer_id        TYPE string,
          lv_product            TYPE string,
          lv_quantity_txt       TYPE string,
          lv_unit_price_txt     TYPE string,
          lv_ship_addr          TYPE string,
          lv_pay_method         TYPE string,
          lv_order_status       TYPE string,
          lv_tracking           TYPE string,
          lv_items_in_cart_txt  TYPE string,
          lv_coupon_code        TYPE string,
          lv_ref_source         TYPE string,
          lv_total_price_txt    TYPE string.

    READ TABLE lt_tokens INDEX 1  INTO lv_order_id.
    READ TABLE lt_tokens INDEX 2  INTO lv_order_date_text.
    READ TABLE lt_tokens INDEX 3  INTO lv_customer_id.
    READ TABLE lt_tokens INDEX 4  INTO lv_product.
    READ TABLE lt_tokens INDEX 5  INTO lv_quantity_txt.
    READ TABLE lt_tokens INDEX 6  INTO lv_unit_price_txt.
    READ TABLE lt_tokens INDEX 7  INTO lv_ship_addr.
    READ TABLE lt_tokens INDEX 8  INTO lv_pay_method.
    READ TABLE lt_tokens INDEX 9  INTO lv_order_status.
    READ TABLE lt_tokens INDEX 10 INTO lv_tracking.
    READ TABLE lt_tokens INDEX 11 INTO lv_items_in_cart_txt.
    READ TABLE lt_tokens INDEX 12 INTO lv_coupon_code.
    READ TABLE lt_tokens INDEX 13 INTO lv_ref_source.
    READ TABLE lt_tokens INDEX 14 INTO lv_total_price_txt.

    " --- Date parse to DATS
    DATA: lv_order_date TYPE d,
          lv_ok         TYPE abap_bool VALUE abap_false.

    IF strlen( lv_order_date_text ) = 10 AND lv_order_date_text+4(1) = '-' AND lv_order_date_text+7(1) = '-'.
      DATA(lv_iso) = lv_order_date_text.
      REPLACE ALL OCCURRENCES OF '-' IN lv_iso WITH ''.
      IF strlen( lv_iso ) = 8.
        lv_order_date = lv_iso.
        lv_ok = abap_true.
      ENDIF.
    ELSEIF strlen( lv_order_date_text ) = 8 AND lv_order_date_text CO '0123456789'.
      lv_order_date = lv_order_date_text.
      lv_ok = abap_true.
    ENDIF.

    IF lv_ok = abap_false.
      CALL FUNCTION 'DATE_CONV_EXT_TO_INT'
        EXPORTING
          i_date_ext = lv_order_date_text
        IMPORTING
          e_date_int = lv_order_date
        EXCEPTIONS
          invalid_date = 1
          OTHERS       = 2.
      IF sy-subrc = 0.
        lv_ok = abap_true.
      ENDIF.
    ENDIF.

    IF lv_ok = abap_false OR lv_order_date IS INITIAL.
      lv_order_date = sy-datum.
      CLEAR ls_ret.
      ls_ret-type    = 'W'.
      ls_ret-id      = 'ZORD'.
      ls_ret-number  = '004'.
      ls_ret-message = |Row { lv_idx }: Order date '{ lv_order_date_text }' not recognized; defaulted to SY-DATUM.|.
      APPEND ls_ret TO et_return.
    ENDIF.

    " --- Segment fill (typed)
    DATA: ls_seg TYPE zonlineorder.
    CLEAR ls_seg.
    ls_seg-order_id        = lv_order_id.
    ls_seg-order_date      = lv_order_date.
    ls_seg-customer_id     = lv_customer_id.
    ls_seg-product         = lv_product.
    WRITE lv_quantity_txt      TO ls_seg-quantity.
    WRITE lv_unit_price_txt    TO ls_seg-unit_price DECIMALS 2.
    ls_seg-ship_address    = lv_ship_addr.
    ls_seg-payment_method  = lv_pay_method.
    ls_seg-order_status    = lv_order_status.
    ls_seg-tracking_number = lv_tracking.
    WRITE lv_items_in_cart_txt TO ls_seg-items_in_cart.
    ls_seg-coupon_code     = lv_coupon_code.
    ls_seg-referral_source = lv_ref_source.
    WRITE lv_total_price_txt   TO ls_seg-total_price DECIMALS 2.

    " --- Branch: inbound vs outbound
    IF iv_direction = 'I'.
      " Inbound (status 64)
      DATA: lt_data TYPE STANDARD TABLE OF edidd WITH DEFAULT KEY,
            ls_data TYPE edidd,
            ls_ctrl TYPE edidc.
      CLEAR: lt_data, ls_data, ls_ctrl.

      ls_data-segnam = iv_segtp.
      ls_data-sdata  = ls_seg.
      APPEND ls_data TO lt_data.

      ls_ctrl-mestyp = iv_mestyp.
      ls_ctrl-idoctp = iv_idoctyp.
      ls_ctrl-direct = '2'.
      ls_ctrl-rcvprt = 'LS'.
      ls_ctrl-rcvprn = 'LOCAL'.
      ls_ctrl-sndprt = 'LS'.
      ls_ctrl-sndprn = 'LOCAL'.

      CALL FUNCTION 'IDOC_INBOUND_WRITE_TO_DB'
        TABLES
          t_data_records    = lt_data
        CHANGING
          pc_control_record = ls_ctrl
        EXCEPTIONS
          OTHERS            = 1.

      IF sy-subrc = 0.
        ev_docnum = ls_ctrl-docnum.
        CLEAR ls_ret.
        ls_ret-type    = 'S'.
        ls_ret-id      = 'ZORD'.
        ls_ret-number  = '010'.
        ls_ret-message = |Row { lv_idx }: Inbound IDoc created (status 64). DOCNUM={ ev_docnum }.|.
        APPEND ls_ret TO et_return.
      ELSE.
        CLEAR ls_ret.
        ls_ret-type    = 'E'.
        ls_ret-id      = 'ZORD'.
        ls_ret-number  = '011'.
        ls_ret-message = |Row { lv_idx }: IDOC_INBOUND_WRITE_TO_DB failed.|.
        APPEND ls_ret TO et_return.
      ENDIF.

    ELSE.

" --- Outbound (create & dispatch all, return all DOCNUMs) -------------
DATA: ls_ctrl_o TYPE edidc,          " EDI_DC40
      ls_data_o TYPE edidd,
      t_ctrl_o  TYPE STANDARD TABLE OF edidc WITH DEFAULT KEY,
      t_data_o  TYPE STANDARD TABLE OF edidd WITH DEFAULT KEY.

CLEAR: ls_ctrl_o, ls_data_o.
CLEAR: t_ctrl_o,  t_data_o.

" Segment record
ls_data_o-segnam = iv_segtp.    " <-- ensure consistency: IV_SEGTYP vs IV_SEGTP
ls_data_o-sdata  = ls_seg.
APPEND ls_data_o TO t_data_o.

" Control record (outbound)
ls_ctrl_o-mestyp = iv_mestyp.
ls_ctrl_o-idoctp = iv_idoctyp.
ls_ctrl_o-direct = '1'.
ls_ctrl_o-sndprt = COND #( WHEN iv_sndprt IS INITIAL THEN 'LS'     ELSE iv_sndprt ).
ls_ctrl_o-sndprn = COND #( WHEN iv_sndprn IS INITIAL THEN 'LOCAL'  ELSE iv_sndprn ).
ls_ctrl_o-rcvprt = COND #( WHEN iv_rcvprt IS INITIAL THEN 'LS'     ELSE iv_rcvprt ).
ls_ctrl_o-rcvprn = COND #( WHEN iv_rcvprn IS INITIAL THEN 'LOCAL'  ELSE iv_rcvprn ).
ls_ctrl_o-rcvpor = iv_rcvpor.

" Append control to the comm table BEFORE calling the FM
APPEND ls_ctrl_o TO t_ctrl_o.

" Create IDoc(s) → status 30
CALL FUNCTION 'MASTER_IDOC_DISTRIBUTE'
  EXPORTING
    master_idoc_control        = ls_ctrl_o
  TABLES
    communication_idoc_control = t_ctrl_o
    master_idoc_data           = t_data_o
  EXCEPTIONS
    error_in_idoc_control          = 1
    error_writing_idoc_status      = 2
    error_in_idoc_data             = 3
    sending_logical_system_unknown = 4
    OTHERS                         = 5.

IF sy-subrc = 0.

  " Collect all DOCNUMs from t_ctrl_o
  REFRESH et_docnums.
  CLEAR   ev_docnum.

  LOOP AT t_ctrl_o INTO ls_ctrl_o WHERE docnum IS NOT INITIAL.
    APPEND ls_ctrl_o-docnum TO et_docnums.  " et_docnums is STANDARD TABLE OF EDI_DOCNUM
    ev_docnum = ls_ctrl_o-docnum.           " keep last for convenience
  ENDLOOP.

  " Optional: dispatch each IDoc immediately (avoid status 30)
  "LOOP AT et_docnums ASSIGNING FIELD-SYMBOL(<docnum>).
    "CALL FUNCTION 'IDOC_START_OUTBOUND'
    "  EXPORTING
    "    idoc_number = <docnum>
     " EXCEPTIONS
     "   OTHERS      = 1.
  "ENDLOOP.

  CALL FUNCTION 'DB_COMMIT'.
  CALL FUNCTION 'DEQUEUE_ALL'.  " or EDI_DOCUMENT_DEQUEUE_LATER for individual IDocs
  COMMIT WORK AND WAIT.

  DATA(lv_cnt) = lines( et_docnums ).
  DATA(lv_msg) = |Outbound IDoc(s) created and dispatched. Count={ lv_cnt }.|.
  CLEAR ls_ret.
  ls_ret-type    = 'S'.
  ls_ret-id      = 'ZORD'.
  ls_ret-number  = '020'.
  ls_ret-message = lv_msg.
  APPEND ls_ret TO et_return.

ELSE.
  CLEAR ls_ret.
  ls_ret-type    = 'E'.
  ls_ret-id      = 'ZORD'.
  ls_ret-number  = '021'.
  ls_ret-message = |MASTER_IDOC_DISTRIBUTE failed (SY-SUBRC={ sy-subrc }).|.
  APPEND ls_ret TO et_return.
ENDIF.


    ENDIF.

  ENDLOOP.

  " Commit once at the end (batch-friendly)
  COMMIT WORK AND WAIT.

ENDFUNCTION.
