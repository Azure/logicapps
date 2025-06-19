<xsl:stylesheet xmlns:ns0="http://tempuri.org/source.xsd" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:math="http://www.w3.org/2005/xpath-functions/math" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dm="http://azure.workflow.datamapper" xmlns:ef="http://azure.workflow.datamapper.extensions" exclude-result-prefixes="xsl xs math dm ef ns0" version="3.0" expand-text="yes">
  <xsl:output indent="yes" media-type="text/xml" method="xml" />
  <xsl:template match="/">
    <xsl:apply-templates select="." mode="azure.workflow.datamapper" />
  </xsl:template>
  <xsl:template match="/" mode="azure.workflow.datamapper">
    <ns0:Root>
      <DirectTranslation>
        <xsl:choose>
          <xsl:when test="/ns0:Root/DirectTranslation/EmployeeID">
            <EmployeeID>{/ns0:Root/DirectTranslation/EmployeeName}</EmployeeID>
          </xsl:when>
        </xsl:choose>
      </DirectTranslation>
      <DataTranslation>
        <Employee>
          <xsl:choose>
            <xsl:when test="(/ns0:Root/DataTranslation/Employee/FirstName) &gt; (/ns0:Root/DataTranslation/Employee/LastName)">
              <FirstName>{/ns0:Root/DataTranslation/Employee/LastName}</FirstName>
            </xsl:when>
          </xsl:choose>
          <xsl:choose>
            <xsl:when test="/ns0:Root/CumulativeExpression/Population/State/Name">
              <LastName>{xs:date(/ns0:Root/CumulativeExpression/Population/State/Name)}</LastName>
            </xsl:when>
          </xsl:choose>
        </Employee>
      </DataTranslation>
    </ns0:Root>
  </xsl:template>
</xsl:stylesheet>