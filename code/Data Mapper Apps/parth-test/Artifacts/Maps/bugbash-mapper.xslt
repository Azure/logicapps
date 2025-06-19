<xsl:stylesheet xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns0="http://www.dnvgl.com/EBS_Integration/masterdata/ProjectInbound" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ns4="https://SchProjectGBO.SchProjectGBO" xmlns:pjc="http://SchCustomerReference.SchCustomerReference" xmlns:b="http://schemas.microsoft.com/BizTalk/2003" xmlns:ns0_0="https://SchProjectGBO.PropertySchema" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:math="http://www.w3.org/2005/xpath-functions/math" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dm="http://azure.workflow.datamapper" xmlns:ef="http://azure.workflow.datamapper.extensions" exclude-result-prefixes="xsl xs math dm ef ns4 pjc b ns0_0" version="3.0" expand-text="yes">
  <xsl:output indent="yes" media-type="text/xml" method="xml" />
  <xsl:template match="/">
    <xsl:apply-templates select="." mode="azure.workflow.datamapper" />
  </xsl:template>
  <xsl:template match="/" mode="azure.workflow.datamapper">
    <soapenv:Envelope>
      <soapenv:Body>
        <ns0:PROJECT_REQUEST_ROOT>
          <ns0:PROJECT_REQUEST>
            <ns0:INTEGRATION_HEADER>
              <ns0:MessageID>{/ns4:projectGBO/OEBS_Header/messageDetails/msgID}</ns0:MessageID>
              <ns0:CorrelationID>{/ns4:projectGBO/OEBS_Header/messageDetails/correlationID}</ns0:CorrelationID>
              <ns0:ResponseLocation>{/ns4:projectGBO/OEBS_Header/messageDetails/ResponseLocation}</ns0:ResponseLocation>
              <ns0:ReceiverSystem>{/ns4:projectGBO/OEBS_Header/messageDetails/ReceiverSystem}</ns0:ReceiverSystem>
              <ns0:SenderSystem>{/ns4:projectGBO/OEBS_Header/messageDetails/SenderSystem}</ns0:SenderSystem>
              <ns0:SentTimeStamp>{/ns4:projectGBO/OEBS_Header/messageDetails/sentTimeStamp}</ns0:SentTimeStamp>
              <ns0:ServiceCallType>{/ns4:projectGBO/OEBS_Header/messageDetails/ServiceCallType}</ns0:ServiceCallType>
            </ns0:INTEGRATION_HEADER>
            <ns0:PROJINTRF>
              <xsl:for-each select="/ns4:projectGBO/project">
                <ns0:PROJECT>
                  <ns0:PM_PROJECT_REFERENCE>{pmProjectReference}</ns0:PM_PROJECT_REFERENCE>
                  <ns0:PA_PROJECT_NUMBER>{paProjectNumber}</ns0:PA_PROJECT_NUMBER>
                  <ns0:PROJECT_TYPE>{projectType}</ns0:PROJECT_TYPE>
                </ns0:PROJECT>
              </xsl:for-each>
            </ns0:PROJINTRF>
          </ns0:PROJECT_REQUEST>
        </ns0:PROJECT_REQUEST_ROOT>
      </soapenv:Body>
    </soapenv:Envelope>
  </xsl:template>
</xsl:stylesheet>