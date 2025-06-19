<xsl:stylesheet xmlns:ns0="http://tempuri.org/Target.xsd" xmlns:td="http://tempuri.org/TypeDefinition.xsd" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ns0_0="http://tempuri.org/source.xsd" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:math="http://www.w3.org/2005/xpath-functions/math" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dm="http://azure.workflow.datamapper" xmlns:ef="http://azure.workflow.datamapper.extensions" exclude-result-prefixes="xsl xs math dm ef ns0_0" version="3.0" expand-text="yes">
  <xsl:output indent="yes" media-type="text/xml" method="xml" />
  <xsl:template match="/">
    <xsl:apply-templates select="." mode="azure.workflow.datamapper" />
  </xsl:template>
  <xsl:template match="/" mode="azure.workflow.datamapper">
    <ns0:Root>
      <DirectTranslation>
        <Employee>
          <ID>{/ns0_0:Root/DirectTranslation/EmployeeID}</ID>
        </Employee>
      </DirectTranslation>
    </ns0:Root>
  </xsl:template>
</xsl:stylesheet>