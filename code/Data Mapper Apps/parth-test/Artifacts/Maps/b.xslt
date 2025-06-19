<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:math="http://www.w3.org/2005/xpath-functions/math" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dm="http://azure.workflow.datamapper" xmlns:ef="http://azure.workflow.datamapper.extensions" xmlns="http://www.w3.org/2005/xpath-functions" exclude-result-prefixes="xsl xs math dm ef" version="3.0" expand-text="yes">
  <xsl:output indent="yes" media-type="text/json" method="text" omit-xml-declaration="yes" />
  <xsl:template match="/">
    <xsl:variable name="xmlinput" select="json-to-xml(/)" />
    <xsl:variable name="xmloutput">
      <xsl:apply-templates select="$xmlinput" mode="azure.workflow.datamapper" />
    </xsl:variable>
    <xsl:value-of select="xml-to-json($xmloutput,map{'indent':true()})" />
  </xsl:template>
  <xsl:template match="/" mode="azure.workflow.datamapper">
    <map>
      <map key="root">
        <map key="outerLoop">
          <map key="innerLoop1">
            <xsl:choose>
              <xsl:when test="local-name-from-QName(node-name(/*/*[@key='root']/*[@key='outerLoop']/*[@key='innerLoop1']/*[@key='name'])) = 'null'">
                <null key="name" />
              </xsl:when>
              <xsl:otherwise>
                <string key="name">{/*/*[@key='root']/*[@key='outerLoop']/*[@key='innerLoop1']/*[@key='name']}</string>
              </xsl:otherwise>
            </xsl:choose>
          </map>
        </map>
      </map>
    </map>
  </xsl:template>
</xsl:stylesheet>