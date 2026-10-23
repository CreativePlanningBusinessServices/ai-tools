<?xml version="1.0" encoding="UTF-8"?>
<!-- Merged BFO XML -> browser HTML. One .bfo-sheet per document; every element carries data-bfo, its position path in the merged XML. -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="UTF-8" indent="no"/>

  <xsl:strip-space elements="table thead tbody tfoot tr ul ol"/>

  <xsl:key name="same-name" match="*" use="concat(generate-id(..), '|', name())"/>

  <xsl:variable name="upper" select="'ABCDEFGHIJKLMNOPQRSTUVWXYZ'"/>
  <xsl:variable name="lower" select="'abcdefghijklmnopqrstuvwxyz'"/>

  <xsl:template match="/">
    <xsl:text disable-output-escaping="yes">&lt;!DOCTYPE html&gt;
</xsl:text>
    <html>
      <head>
        <meta charset="UTF-8"/>
        <title>PDF template preview</title>
        <style>
          body { margin: 0; background: #d9d9d9; }
          .bfo-sheet { box-sizing: border-box; display: flex; flex-direction: column; margin: 16px auto; background: #fff;
            box-shadow: 0 1px 6px rgba(0,0,0,.35); font-family: sans-serif; }
          .bfo-content { flex: 1; }
          .bfo-pbr { border-top: 2px dashed #b3261e; margin: 12px 0; position: relative; height: 0; }
          .bfo-pbr::after { content: "page break"; position: absolute; right: 0; top: -9px; background: #fff; color: #b3261e; font: 10px sans-serif; padding: 0 4px; }
          .bfo-barcode { display: inline-block; border: 1px solid #555; padding: 4px 8px; font: 11px monospace; }
          .bfo-size-note { background: #fff7e6; border: 1px solid #e6c576; padding: 4px 8px; font: 12px sans-serif; margin-bottom: 8px; }
          [data-bfo]:hover { outline: 1px dotted #165D7D; }
        </style>
        <xsl:for-each select="/pdf/head/style | /html/head/style | /pdfset/*/head/style">
          <style><xsl:value-of select="."/></style>
        </xsl:for-each>
      </head>
      <body>
        <xsl:apply-templates select="/pdf | /html | /pdfset/*" mode="sheet"/>
      </body>
    </html>
  </xsl:template>

  <xsl:template match="*" mode="sheet">
    <xsl:variable name="body" select="body"/>
    <xsl:variable name="size" select="translate(normalize-space($body/@size), $upper, $lower)"/>
    <xsl:variable name="known" select="$size = '' or $size = 'letter' or $size = 'a4' or $size = 'letter-landscape' or $size = 'a4-landscape'"/>
    <xsl:variable name="width">
      <xsl:choose>
        <xsl:when test="$size = 'a4'">210mm</xsl:when>
        <xsl:when test="$size = 'a4-landscape'">297mm</xsl:when>
        <xsl:when test="$size = 'letter-landscape'">11in</xsl:when>
        <xsl:otherwise>8.5in</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="height">
      <xsl:choose>
        <xsl:when test="$size = 'a4'">297mm</xsl:when>
        <xsl:when test="$size = 'a4-landscape'">210mm</xsl:when>
        <xsl:when test="$size = 'letter-landscape'">8.5in</xsl:when>
        <xsl:otherwise>11in</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="padding">
      <xsl:choose>
        <xsl:when test="$body/@padding"><xsl:value-of select="$body/@padding"/></xsl:when>
        <xsl:when test="$body/@margin"><xsl:value-of select="$body/@margin"/></xsl:when>
        <xsl:otherwise>0.5in</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <div class="bfo-sheet" style="width: {$width}; min-height: {$height}; padding: {$padding};">
      <xsl:if test="not($known)">
        <div class="bfo-size-note">Page size "<xsl:value-of select="$body/@size"/>" is not known to the twin; shown as Letter.</div>
      </xsl:if>
      <xsl:apply-templates select="head/macrolist/macro[@id = $body/@header]" mode="macro"/>
      <div class="bfo-content">
        <xsl:for-each select="body">
          <xsl:call-template name="children">
            <xsl:with-param name="path"><xsl:call-template name="ancestor-path"/></xsl:with-param>
          </xsl:call-template>
        </xsl:for-each>
      </div>
      <xsl:apply-templates select="head/macrolist/macro[@id = $body/@footer]" mode="macro"/>
    </div>
  </xsl:template>

  <xsl:template match="macro" mode="macro">
    <div class="bfo-macro">
      <xsl:call-template name="children">
        <xsl:with-param name="path"><xsl:call-template name="ancestor-path"/></xsl:with-param>
      </xsl:call-template>
    </div>
  </xsl:template>

  <!-- parent-path / same-name-index come from the parent's `children`. A same-name-index above 0 is the element's position
       among same-name siblings, known without scanning; otherwise xsl:number scans. -->
  <xsl:template match="*">
    <xsl:param name="parent-path" select="''"/>
    <xsl:param name="same-name-index" select="0"/>
    <xsl:variable name="path">
      <xsl:call-template name="step-path">
        <xsl:with-param name="parent-path" select="$parent-path"/>
        <xsl:with-param name="same-name-index" select="$same-name-index"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:attribute name="data-bfo"><xsl:value-of select="$path"/></xsl:attribute>
      <xsl:call-template name="children"><xsl:with-param name="path" select="$path"/></xsl:call-template>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="pbr">
    <xsl:param name="parent-path" select="''"/>
    <xsl:param name="same-name-index" select="0"/>
    <div class="bfo-pbr">
      <xsl:attribute name="data-bfo">
        <xsl:call-template name="step-path">
          <xsl:with-param name="parent-path" select="$parent-path"/>
          <xsl:with-param name="same-name-index" select="$same-name-index"/>
        </xsl:call-template>
      </xsl:attribute>
    </div>
  </xsl:template>

  <xsl:template match="pagenumber"><span class="bfo-pagenumber">1</span></xsl:template>
  <xsl:template match="totalpages"><span class="bfo-totalpages">N</span></xsl:template>

  <xsl:template match="barcode">
    <xsl:param name="parent-path" select="''"/>
    <xsl:param name="same-name-index" select="0"/>
    <div class="bfo-barcode">
      <xsl:attribute name="data-bfo">
        <xsl:call-template name="step-path">
          <xsl:with-param name="parent-path" select="$parent-path"/>
          <xsl:with-param name="same-name-index" select="$same-name-index"/>
        </xsl:call-template>
      </xsl:attribute>
      <xsl:value-of select="@codetype"/>: <span><xsl:value-of select="@value"/></span>
    </div>
  </xsl:template>

  <xsl:template match="link"/>

  <!-- Context = the parent element. xsl:number scans the preceding siblings of each child, which is quadratic for a long run of rows.
       The children named like the middle element are usually one unbroken run (a table's rows, maybe after a thead), so when they are,
       position() minus the run's offset is their same-name index; other children fall back to xsl:number. -->
  <xsl:template name="children">
    <xsl:param name="path"/>
    <xsl:variable name="pivot" select="name(*[ceiling(count(*) div 2)])"/>
    <xsl:variable name="pivot-nodes" select="key('same-name', concat(generate-id(), '|', $pivot))"/>
    <xsl:variable name="pivot-start" select="count($pivot-nodes[1]/preceding-sibling::node())"/>
    <xsl:variable name="pivot-contiguous" select="$pivot != '' and count($pivot-nodes[last()]/preceding-sibling::node()) - $pivot-start + 1 = count($pivot-nodes)"/>
    <xsl:for-each select="node()">
      <xsl:apply-templates select=".">
        <xsl:with-param name="parent-path" select="$path"/>
        <xsl:with-param name="same-name-index" select="number($pivot-contiguous and name() = $pivot) * (position() - $pivot-start)"/>
      </xsl:apply-templates>
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="step-path">
    <xsl:param name="parent-path"/>
    <xsl:param name="same-name-index"/>
    <xsl:value-of select="$parent-path"/>
    <xsl:text>/</xsl:text>
    <xsl:value-of select="name()"/>
    <xsl:if test="parent::* and not(self::head or self::body or self::macrolist)">
      <xsl:text>[</xsl:text>
      <xsl:choose>
        <xsl:when test="$same-name-index &gt; 0"><xsl:value-of select="$same-name-index"/></xsl:when>
        <xsl:otherwise><xsl:number level="single"/></xsl:otherwise>
      </xsl:choose>
      <xsl:text>]</xsl:text>
    </xsl:if>
  </xsl:template>

  <!-- Only for the few structural elements (document, body, macro); scans siblings. -->
  <xsl:template name="ancestor-path">
    <xsl:for-each select="ancestor-or-self::*">
      <xsl:call-template name="step-path"><xsl:with-param name="same-name-index" select="0"/></xsl:call-template>
    </xsl:for-each>
  </xsl:template>
</xsl:stylesheet>
