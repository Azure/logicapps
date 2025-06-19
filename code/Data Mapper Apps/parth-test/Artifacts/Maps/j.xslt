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
              <ns0:ReceiverSystem>{/ns4:projectGBO/OEBS_Header/messageDetails/ReceiverSystem}</ns0:ReceiverSystem>
              <ns0:SenderSystem>{/ns4:projectGBO/OEBS_Header/messageDetails/SenderSystem}</ns0:SenderSystem>
            </ns0:INTEGRATION_HEADER>
            <ns0:PROJINTRF>
              <xsl:for-each select="/ns4:projectGBO/project">
                <ns0:PROJECT>
                  <ns0:TASKS>
                    <xsl:for-each select="/ns4:projectGBO/project">
                      <xsl:for-each select="task">
                        <ns0:TASK>
                          <xsl:choose>
                            <xsl:when test="(/ns4:projectGBO/project/feeRate) &gt; (10000)">
                              <ns0:TASK_ID>{/ns4:projectGBO/project/task/taskID}</ns0:TASK_ID>
                              <ns0:TASK_NUMBER>{/ns4:projectGBO/project/task/taskNumber}</ns0:TASK_NUMBER>
                              <ns0:LONG_TASK_NAME>{/ns4:projectGBO/project/task/taskName}</ns0:LONG_TASK_NAME>
                              <ns0:PM_PARENT_TASK_REFERENCE>{number(/ns4:projectGBO/project/task/pmParentReference) idiv 1}</ns0:PM_PARENT_TASK_REFERENCE>
                            </xsl:when>
                          </xsl:choose>
                          <ns0:TASK_NAME>{../feeRate}</ns0:TASK_NAME>
                          <ns0:ATTRIBUTE1>{attribute1}</ns0:ATTRIBUTE1>
                        </ns0:TASK>
                      </xsl:for-each>
                    </xsl:for-each>
                  </ns0:TASKS>
                  <xsl:choose>
                    <xsl:when test="(feeRate) &gt; (10000)">
                      <ns0:ATTRIBUTE1>{serviceCode}</ns0:ATTRIBUTE1>
                      <ns0:ATTRIBUTE10>{task/attribute14}</ns0:ATTRIBUTE10>
                    </xsl:when>
                  </xsl:choose>
                </ns0:PROJECT>
              </xsl:for-each>
            </ns0:PROJINTRF>
          </ns0:PROJECT_REQUEST>
        </ns0:PROJECT_REQUEST_ROOT>
      </soapenv:Body>
    </soapenv:Envelope>
  </xsl:template>
</xsl:stylesheet>