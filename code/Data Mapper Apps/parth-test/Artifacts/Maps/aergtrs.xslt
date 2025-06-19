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
            <xsl:for-each select="budgets/budget">
              <tns:PROJECT>
                <tns:FEE_PERCENTAGE>{../../feePercentage}</tns:FEE_PERCENTAGE>
                <tns:TASKS>
                  <xsl:for-each select="/ns4:projectGBO/project">
                    <xsl:for-each select="budgetLines/budgetLine">
                      <xsl:for-each select="task">
                        <tns:TASK>
                          <xsl:choose>
                            <xsl:when test="(number(/ns4:projectGBO/project/feeRate) idiv 1) &gt;= (1000)">
                              <tns:PM_TASK_REFERENCE>{/ns4:projectGBO/project/budgets/budget/budgetLines/budgetLine/pmTaskReference}</tns:PM_TASK_REFERENCE>
                              <tns:TASK_ID>{/ns4:projectGBO/project/task/taskID}</tns:TASK_ID>
                            </xsl:when>
                          </xsl:choose>
                        </tns:TASK>
                      </xsl:for-each>
                    </xsl:for-each>
                  </xsl:for-each>
                </tns:TASKS>
                <xsl:choose>
                  <xsl:when test="(number(/ns4:projectGBO/project/feeRate) idiv 1) &gt;= (1000)">
                    <tns:BILL_GROUP_NAME>{/ns4:projectGBO/project/billGroupName}</tns:BILL_GROUP_NAME>
                  </xsl:when>
                </xsl:choose>
              </tns:PROJECT>
            </xsl:for-each>
          </xsl:for-each>
        </tns:PROJINTRF>
      </tns:PROJECT_REQUEST>
    </tns:PROJECT_REQUEST_ROOT>
  </xsl:template>
</xsl:stylesheet>