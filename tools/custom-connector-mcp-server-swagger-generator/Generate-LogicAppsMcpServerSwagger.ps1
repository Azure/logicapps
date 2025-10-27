<#
.SYNOPSIS
    Generates a Logic Apps Custom Connector swagger file for building an MCP server from a config file.

.DESCRIPTION
    This script reads a JSON configuration file and applies them to an inline swagger template
    to generate a customized swagger definition for Logic Apps Custom Connector MCP Server.

.PARAMETER ConfigPath
    Path to the JSON configuration file containing placeholder values.

.PARAMETER OutputPath
    Path where the generated swagger file will be saved. If not specified, generates based on config name.

.EXAMPLE
    .\Generate-LogicAppsMcpServerSwagger.ps1 -ConfigPath "config.json"
    
.EXAMPLE
    .\Generate-LogicAppsMcpServerSwagger.ps1 -ConfigPath "myserver-config.json" -OutputPath "myserver-swagger.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

# Inline swagger template
$swaggerTemplate = @'
{
    "swagger": "2.0",
    "info": {
        "title": "Logic Apps Custom Connector MCP Server",
        "description": "Logic Apps Custom Connector MCP Server.",
        "version": "1.0.0"
    },
    "host": "${host}",
    "basePath": "/",
    "schemes": [
        "${httpScheme}"
    ],
    "consumes": [
        "application/json"
    ],
    "produces": [
        "application/json"
    ],
    "paths": {
        "${path}": {
            "post": {
                "summary": "${mcpServerName}",
                "operationId": "InvokeMCP",
                "responses": {
                    "200": {
                        "description": "Success"
                    }
                },
                "description": "${mcpServerDescription}",
                "parameters": [
                    {
                        "in": "header",
                        "name": "Mcp-Session-Id",
                        "required": false,
                        "type": "string",
                        "description": "This is the MCP session ID",
                        "x-ms-summary": "MCP Session Id"
                    },
                    {
                        "in": "body",
                        "name": "queryRequest",
                        "required": false,
                        "schema": {
                            "$ref": "#/definitions/QueryRequest"
                        }
                    }
                ],
                "produces": [
                    "application/json"
                ],
                "tags": [
                    "Agentic",
                    "McpStreamable"
                ]
            }
        }
    },
    "definitions": {
        "QueryRequest": {
            "type": "object",
            "properties": {
                "jsonrpc": {
                    "type": "string"
                },
                "id": {
                    "type": "string"
                },
                "method": {
                    "type": "string"
                },
                "params": {
                    "type": "object"
                },
                "result": {
                    "type": "object"
                },
                "error": {
                    "type": "object"
                }
            }
        }
    },
    "securityDefinitions": {},
    "security": [],
    "tags": []
}
'@

function ConvertFrom-Url {
    param([string]$Url)
    
    try {
        $uri = [System.Uri]$Url
        
        # Extract components
        $scheme = $uri.Scheme
        $hostName = $uri.Host
        $path = $uri.AbsolutePath
        
        # Handle port if present
        if ($uri.Port -ne -1 -and $uri.Port -ne 80 -and $uri.Port -ne 443) {
            $hostName = "$($uri.Host):$($uri.Port)"
        }
        
        # Ensure path starts with /
        if (-not $path.StartsWith('/')) {
            $path = "/$path"
        }
        
        # If path is just "/", set it to a default
        if ($path -eq '/') {
            $path = '/api/mcp'
        }
        
        return @{
            httpScheme = $scheme
            host = $hostName
            path = $path
        }
    }
    catch {
        Write-Error "Invalid URL format: $Url. Please provide a valid URL (e.g., 'https://myserver.azurewebsites.net/api/mcp')"
        exit 1
    }
}

function Update-Placeholders {
    param(
        [string]$TemplateContent,
        [PSCustomObject]$Config
    )
    
    $result = $TemplateContent
    $replacedCount = 0
    $replacedPlaceholders = @()
    
    # Replace each placeholder with the corresponding value from config
    $config.PSObject.Properties | ForEach-Object {
        $placeholder = "`${$($_.Name)}"
        $value = $_.Value
        
        if ($result.Contains($placeholder)) {
            Write-Verbose "Replacing placeholder '$placeholder' with '$value'"
            $result = $result.Replace($placeholder, $value)
            $replacedCount++
            $replacedPlaceholders += $_.Name
        }
        else {
            Write-Warning "Placeholder '$placeholder' not found in template"
        }
    }
    
    # Check for any remaining placeholders - ${} format
    $remainingPlaceholders = [regex]::Matches($result, '\$\{[^}]+\}')
    if ($remainingPlaceholders.Count -gt 0) {
        Write-Warning "The following placeholders were not replaced:"
        $remainingPlaceholders | ForEach-Object { Write-Warning "  $($_.Value)" }
    }
    
    # Return both the result and metadata
    return @{
        Content = $result
        ReplacedCount = $replacedCount
        ReplacedPlaceholders = $replacedPlaceholders
    }
}

function Test-FileExists {
    param([string]$FilePath, [string]$FileType)
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "$FileType file not found: $FilePath"
        exit 1
    }
}

function Read-JsonFile {
    param([string]$FilePath)
    
    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        return $content | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to read or parse JSON file '$FilePath': $($_.Exception.Message)"
        exit 1
    }
}

function Get-OutputPath {
    param([string]$ConfigPath)
    
    $configBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    $directory = [System.IO.Path]::GetDirectoryName($ConfigPath)
    
    if ([string]::IsNullOrEmpty($directory)) {
        $directory = "."
    }
    
    return Join-Path $directory "$configBaseName-swagger.json"
}

function Test-Config {
    param([PSCustomObject]$Config)
    
    $requiredFields = @("url", "mcpServerName", "mcpServerDescription")
    $missingFields = @()
    
    foreach ($field in $requiredFields) {
        if (-not $Config.PSObject.Properties.Name.Contains($field)) {
            $missingFields += $field
        }
        elseif ([string]::IsNullOrWhiteSpace($Config.$field)) {
            $missingFields += "$field (empty or whitespace)"
        }
    }
    
    if ($missingFields.Count -gt 0) {
        Write-Error "Missing or empty required configuration fields: $($missingFields -join ', ')"
        Write-Host "Required fields: $($requiredFields -join ', ')" -ForegroundColor Yellow
        exit 1
    }
}

function Format-JsonOutput {
    param([string]$JsonString)
    
    try {
        # Parse and reformat to ensure proper JSON formatting
        $jsonObject = $JsonString | ConvertFrom-Json
        return $jsonObject | ConvertTo-Json -Depth 10
    }
    catch {
        Write-Warning "Could not reformat JSON output. Using original formatting."
        return $JsonString
    }
}

# Main execution
Write-Host "Logic Apps Custom Connector Swagger Generator" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

# Validate input files
Test-FileExists -FilePath $ConfigPath -FileType "Configuration"

# Generate output path if not provided
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Get-OutputPath -ConfigPath $ConfigPath
}

Write-Host "Configuration file: $ConfigPath" -ForegroundColor Cyan
Write-Host "Output file: $OutputPath" -ForegroundColor Cyan
Write-Host ""

# Read configuration file
Write-Host -NoNewLine "1/6 Reading configuration..." -ForegroundColor Yellow
$config = Read-JsonFile -FilePath $ConfigPath
Write-Host "    Done!" -ForegroundColor Green

# Validate configuration
Write-Host -NoNewLine "2/6 Validating configuration..." -ForegroundColor Yellow
Test-Config -Config $config
Write-Host "    Done!" -ForegroundColor Green

# Parse URL and extract components
Write-Host -NoNewLine "3/6 Parsing URL..." -ForegroundColor Yellow
$urlComponents = ConvertFrom-Url -Url $config.url
Write-Host "    Done!" -ForegroundColor Green
Write-Verbose "Extracted - Scheme: $($urlComponents.httpScheme), Host: $($urlComponents.host), Path: $($urlComponents.path)"

# Add URL components to config
$enhancedConfig = [PSCustomObject]@{
    httpScheme = $urlComponents.httpScheme
    host = $urlComponents.host
    path = $urlComponents.path
    mcpServerName = $config.mcpServerName
    mcpServerDescription = $config.mcpServerDescription
}

# Replace placeholders using inline template
Write-Host -NoNewLine "4/6 Building swagger..." -ForegroundColor Yellow
$placeholderResult = Update-Placeholders -TemplateContent $swaggerTemplate -Config $enhancedConfig
$generatedContent = $placeholderResult.Content
Write-Host "    Done!" -ForegroundColor Green

# Format the output JSON
Write-Host -NoNewLine "5/6 Formatting swagger..." -ForegroundColor Yellow
$formattedContent = Format-JsonOutput -JsonString $generatedContent
Write-Host "    Done!" -ForegroundColor Green

# Write output file
Write-Host -NoNewLine "6/6 Generating output file..." -ForegroundColor Yellow
try {
    $formattedContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "    Done!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Successfully generated swagger file: $OutputPath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to write output file '$OutputPath': $($_.Exception.Message)"
    exit 1
}

# Display summary
Write-Host ""
Write-Host "Swagger Generation Summary:" -ForegroundColor Green
Write-Host "  Configuration: $ConfigPath"
Write-Host "  URL: $($config.url)"
Write-Host "  Extracted Scheme: $($urlComponents.httpScheme)"
Write-Host "  Extracted Host: $($urlComponents.host)"
Write-Host "  Extracted Path: $($urlComponents.path)"
Write-Host "  Output: $OutputPath"
Write-Host "  Placeholders replaced: $($placeholderResult.ReplacedCount)"
Write-Host "  Replaced: $($placeholderResult.ReplacedPlaceholders -join ', ')"
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "All Done!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

# End of Script