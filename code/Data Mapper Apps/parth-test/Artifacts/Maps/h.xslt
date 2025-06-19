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
              <ns0:MessageID>{(/ns4:projectGBO/OEBS_Header/messageDetails/msgID) + (/ns4:projectGBO/OEBS_Header/messageDetails/correlationID)}</ns0:MessageID>
              <ns0:ResponseLocation>{/ns4:projectGBO/OEBS_Header/messageDetails/requestedOperation}</ns0:ResponseLocation>
            </ns0:INTEGRATION_HEADER>
          </ns0:PROJECT_REQUEST>
        </ns0:PROJECT_REQUEST_ROOT>
      </soapenv:Body>
    </soapenv:Envelope>
  </xsl:template>
</xsl:stylesheet>