<xsl:stylesheet xmlns:tns="http://www.dnvgl.com/EBS_Integration/masterdata/ProjectInbound" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ns4="https://SchProjectGBO.SchProjectGBO" xmlns:pjc="http://SchCustomerReference.SchCustomerReference" xmlns:b="http://schemas.microsoft.com/BizTalk/2003" xmlns:ns0="https://SchProjectGBO.PropertySchema" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:math="http://www.w3.org/2005/xpath-functions/math" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dm="http://azure.workflow.datamapper" xmlns:ef="http://azure.workflow.datamapper.extensions" exclude-result-prefixes="xsl xs math dm ef ns4 pjc b ns0" version="3.0" expand-text="yes">
  <xsl:output indent="yes" media-type="text/xml" method="xml" />
  <xsl:template match="/">
    <xsl:apply-templates select="." mode="azure.workflow.datamapper" />
  </xsl:template>
  <xsl:template match="/" mode="azure.workflow.datamapper">
    <tns:PROJECT_REQUEST_ROOT>
      <tns:PROJECT_REQUEST>
        <tns:PROJINTRF>
          <xsl:for-each select="/ns4:projectGBO/project">
            <tns:PROJECT>
              <tns:PROJECT_TYPE>{paProjectNumber}</tns:PROJECT_TYPE>
              <tns:TASKS>
                <xsl:for-each select="/ns4:projectGBO/project">
                  <xsl:for-each select="task">
                    <tns:TASK>
                      <tns:PM_TASK_REFERENCE>{pmTaskReference}</tns:PM_TASK_REFERENCE>
                      <tns:TASK_ID>{../enableTopTaskInvMthFlag}</tns:TASK_ID>
                    </tns:TASK>
                  </xsl:for-each>
                </xsl:for-each>
              </tns:TASKS>
            </tns:PROJECT>
          </xsl:for-each>
        </tns:PROJINTRF>
      </tns:PROJECT_REQUEST>
    </tns:PROJECT_REQUEST_ROOT>
  </xsl:template>
</xsl:stylesheet>