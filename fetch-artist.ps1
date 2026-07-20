param(
    [Parameter(Mandatory = $true)][string]$ArtistBase64,
    [Parameter(Mandatory = $true)][string]$ArtistRootBase64,
    [Parameter(Mandatory = $true)][string]$LogPathBase64
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function From-Base64Text([string]$Value) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$ArtistName = From-Base64Text $ArtistBase64
$ArtistRoot = From-Base64Text $ArtistRootBase64
$LogPath = From-Base64Text $LogPathBase64

function Write-Log([string]$Message) {
    try {
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {}
}

function Normalize-Text([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function Remove-Diacritics([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }
    return $builder.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Get-SafeArtistKey([string]$Text) {
    $value = (Remove-Diacritics (Normalize-Text $Text)).ToLowerInvariant()
    $value = [regex]::Replace($value, '[^a-z0-9]+', '-')
    return $value.Trim('-')
}

function Invoke-Http([string]$Url, [bool]$Binary = $false) {
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Method = 'GET'
    $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
    $request.Accept = if ($Binary) { 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' } else { 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }
    $request.Timeout = 6500
    $request.ReadWriteTimeout = 6500
    $request.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $response = $null
    $stream = $null
    try {
        $response = [Net.HttpWebResponse]$request.GetResponse()
        $stream = $response.GetResponseStream()
        if ($Binary) {
            $memory = New-Object IO.MemoryStream
            try {
                $stream.CopyTo($memory)
                return [pscustomobject]@{
                    Bytes = $memory.ToArray()
                    ContentType = Normalize-Text $response.ContentType
                    FinalUrl = $response.ResponseUri.AbsoluteUri
                }
            } finally { $memory.Dispose() }
        }
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    } finally {
        if ($null -ne $stream) { try { $stream.Dispose() } catch {} }
        if ($null -ne $response) { try { $response.Dispose() } catch {} }
    }
}

function Html-Decode([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return [Net.WebUtility]::HtmlDecode($Value).Replace('\\u0026', '&')
}

function Resolve-DeezerArtistImageUrl {
    try {
        $url = 'https://api.deezer.com/search/artist?q=' + [Uri]::EscapeDataString($ArtistName) + '&limit=1'
        $result = (Invoke-Http $url) | ConvertFrom-Json
        if ($null -eq $result -or $null -eq $result.data -or $result.data.Count -eq 0) { return $null }
        $artist = $result.data[0]
        foreach ($property in @('picture_xl', 'picture_big', 'picture_medium')) {
            $value = Normalize-Text $artist.$property
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    } catch {
        Write-Log "Deezer sanatci aramasi hatasi ($ArtistName): $($_.Exception.Message)"
    }
    return $null
}

function Get-ArtistPageUrl([string]$Html) {
    $match = [regex]::Match($Html, 'href=["''](?<href>/music/[^"''#?]+)["'']', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }
    try { return ([Uri]::new([Uri]'https://www.last.fm', (Html-Decode $match.Groups['href'].Value))).AbsoluteUri }
    catch { return $null }
}

function Get-FastSearchThumbnail([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $artistLink = [regex]::Match($Html, 'href=["''](?<href>/music/[^"''#?]+)["'']', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $window = $Html
    if ($artistLink.Success) {
        $start = [Math]::Max(0, $artistLink.Index - 1800)
        $length = [Math]::Min($Html.Length - $start, 5200)
        $window = $Html.Substring($start, $length)
    }

    $patterns = @(
        '(?:src|data-src)=["''](?<url>https://lastfm\.freetls\.fastly\.net/i/u/[^"'']+)',
        'srcset=["''][^"'']*(?<url>https://lastfm\.freetls\.fastly\.net/i/u/[^\s,"'']+)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($window, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { return Html-Decode $match.Groups['url'].Value }
    }
    return $null
}

function Get-OgImage([string]$Html) {
    $patterns = @(
        '<meta[^>]+property=["'']og:image["''][^>]+content=["''](?<url>[^"'']+)',
        '<meta[^>]+content=["''](?<url>[^"'']+)["''][^>]+property=["'']og:image["'']',
        '<meta[^>]+name=["'']twitter:image["''][^>]+content=["''](?<url>[^"'']+)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { return Html-Decode $match.Groups['url'].Value }
    }
    return $null
}

function Get-ImageExtension([byte[]]$Bytes, [string]$ContentType) {
    $type = (Normalize-Text $ContentType).ToLowerInvariant()
    if ($Bytes.Length -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return '.png' }
    if ($Bytes.Length -ge 12 -and [Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($Bytes, 8, 4) -eq 'WEBP') { return '.webp' }
    if ($type.Contains('png')) { return '.png' }
    if ($type.Contains('webp')) { return '.webp' }
    return '.jpg'
}

$key = Get-SafeArtistKey $ArtistName
if ([string]::IsNullOrWhiteSpace($key)) { exit 2 }
$fetchingPath = Join-Path $ArtistRoot ($key + '.fetching')
$failedPath = Join-Path $ArtistRoot ($key + '.failed')

try {
    # Deezer'in herkese acik API'si ana kaynaktir ve API anahtari gerektirmez.
    $imageUrl = Resolve-DeezerArtistImageUrl

    # Deezer'da sonuc yoksa mevcut Last.fm web aramasina dus.
    if ([string]::IsNullOrWhiteSpace($imageUrl)) {
        $searchUrl = 'https://www.last.fm/search/artists?q=' + [Uri]::EscapeDataString($ArtistName)
        $searchHtml = Invoke-Http $searchUrl
        $imageUrl = Get-FastSearchThumbnail $searchHtml
        if ([string]::IsNullOrWhiteSpace($imageUrl)) {
            $artistPage = Get-ArtistPageUrl $searchHtml
            if (-not [string]::IsNullOrWhiteSpace($artistPage)) {
                $artistHtml = Invoke-Http $artistPage
                $imageUrl = Get-OgImage $artistHtml
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($imageUrl)) { throw 'Sanatci gorseli URL bulunamadi.' }
    $image = Invoke-Http $imageUrl $true
    if ($null -eq $image -or $null -eq $image.Bytes -or $image.Bytes.Length -lt 512) { throw 'Sanatci gorseli indirilemedi.' }

    foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp')) {
        Remove-Item -LiteralPath (Join-Path $ArtistRoot ($key + $ext)) -Force -ErrorAction SilentlyContinue
    }

    $extension = Get-ImageExtension $image.Bytes $image.ContentType
    $targetPath = Join-Path $ArtistRoot ($key + $extension)
    $tempPath = $targetPath + '.tmp'
    [IO.File]::WriteAllBytes($tempPath, $image.Bytes)
    Move-Item -LiteralPath $tempPath -Destination $targetPath -Force
    Remove-Item -LiteralPath $failedPath -Force -ErrorAction SilentlyContinue
    Write-Log "Sanatci gorseli cache'e alindi: $ArtistName"
} catch {
    try { Set-Content -LiteralPath $failedPath -Value $_.Exception.Message -Encoding UTF8 } catch {}
    Write-Log "Sanatci gorseli indirilemedi ($ArtistName): $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item -LiteralPath $fetchingPath -Force -ErrorAction SilentlyContinue
}
