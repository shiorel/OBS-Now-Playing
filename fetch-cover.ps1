param(
    [Parameter(Mandatory = $true)][string]$ArtistBase64,
    [Parameter(Mandatory = $true)][string]$TitleBase64,
    [Parameter(Mandatory = $true)][string]$AlbumBase64,
    [Parameter(Mandatory = $true)][string]$CoverRootBase64,
    [Parameter(Mandatory = $true)][string]$LogPathBase64
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function From-Base64Text([string]$Value) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$Artist = From-Base64Text $ArtistBase64
$Title = From-Base64Text $TitleBase64
$Album = From-Base64Text $AlbumBase64
$CoverRoot = From-Base64Text $CoverRootBase64
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

function Get-SafeTrackKey([string]$ArtistText, [string]$TitleText, [string]$AlbumText) {
    $raw = ((Normalize-Text $ArtistText).ToLowerInvariant() + '|' + (Normalize-Text $TitleText).ToLowerInvariant() + '|' + (Normalize-Text $AlbumText).ToLowerInvariant())
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Invoke-Http([string]$Url, [bool]$Binary = $false) {
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Method = 'GET'
    $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
    $request.Headers['Accept-Language'] = 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7'
    $request.Accept = if ($Binary) { 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' } else { 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }
    $request.Timeout = 6500
    $request.ReadWriteTimeout = 6500
    $request.AllowAutoRedirect = $true
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
    $decoded = [Net.WebUtility]::HtmlDecode($Value)
    $decoded = $decoded.Replace('\u0026', '&').Replace('\u003d', '=').Replace('\u002F', '/').Replace('\/', '/')
    return $decoded
}

function Resolve-DeezerCoverUrl {
    $queries = @()
    if (-not [string]::IsNullOrWhiteSpace($Artist) -and -not [string]::IsNullOrWhiteSpace($Title)) {
        $queries += 'artist:"' + $Artist + '" track:"' + $Title + '"'
    }
    $queries += ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Title)).Trim()
    if (-not [string]::IsNullOrWhiteSpace($Album)) {
        $queries += ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Album)).Trim()
    }

    foreach ($query in $queries) {
        if ([string]::IsNullOrWhiteSpace($query)) { continue }
        try {
            $url = 'https://api.deezer.com/search?q=' + [Uri]::EscapeDataString($query) + '&limit=1'
            $result = (Invoke-Http $url) | ConvertFrom-Json
            if ($null -eq $result -or $null -eq $result.data -or $result.data.Count -eq 0) { continue }
            $albumResult = $result.data[0].album
            if ($null -eq $albumResult) { continue }
            foreach ($property in @('cover_xl', 'cover_big', 'cover_medium')) {
                $value = Normalize-Text $albumResult.$property
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        } catch {
            Write-Log "Deezer kapak aramasi hatasi ($query): $($_.Exception.Message)"
        }
    }
    return $null
}

function Resolve-ITunesCoverUrl {
    $queries = @(
        ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Title)).Trim(),
        ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Album)).Trim()
    ) | Select-Object -Unique
    foreach ($query in $queries) {
        if ([string]::IsNullOrWhiteSpace($query)) { continue }
        try {
            $url = 'https://itunes.apple.com/search?media=music&entity=song&limit=5&term=' + [Uri]::EscapeDataString($query)
            $result = (Invoke-Http $url) | ConvertFrom-Json
            foreach ($item in @($result.results)) {
                $artwork = Normalize-Text $item.artworkUrl100
                if (-not [string]::IsNullOrWhiteSpace($artwork)) {
                    return ($artwork -replace '100x100bb', '1200x1200bb')
                }
            }
        } catch {
            Write-Log "iTunes kapak aramasi hatasi ($query): $($_.Exception.Message)"
        }
    }
    return $null
}

function Upgrade-LastFmImage([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $value = Html-Decode $Url
    $value = [regex]::Replace($value, '/i/u/(?:34s|64s|64x64|85s|174s|174x174|300x300)/', '/i/u/500x500/', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $value
}

function Is-UsableImageUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $lower = $Url.ToLowerInvariant()
    if ($lower.Contains('2a96cbd8b46e442fc41c2b86b821562f')) { return $false }
    return ($lower.Contains('lastfm.freetls.fastly.net/i/u/') -or
            $lower.Contains('i.scdn.co/image/') -or
            $lower.Contains('image-cdn-ak.spotifycdn.com/image/') -or
            $lower.Contains('mosaic.scdn.co/'))
}

function Get-OgImage([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $patterns = @(
        '<meta[^>]+property=["'']og:image["''][^>]+content=["''](?<url>[^"'']+)',
        '<meta[^>]+content=["''](?<url>[^"'']+)["''][^>]+property=["'']og:image["'']',
        '<meta[^>]+name=["'']twitter:image["''][^>]+content=["''](?<url>[^"'']+)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $candidate = Upgrade-LastFmImage $match.Groups['url'].Value
            if (Is-UsableImageUrl $candidate) { return $candidate }
        }
    }
    return $null
}

function Get-FirstTrackPage([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $patterns = @(
        'href=["''](?<href>/music/[^"''#?]+/_/[^"''#?]+)["'']',
        'href=["''](?<href>/music/[^"''#?]+/[^"''#?]+)["'']'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            try { return ([Uri]::new([Uri]'https://www.last.fm', (Html-Decode $match.Groups['href'].Value))).AbsoluteUri }
            catch {}
        }
    }
    return $null
}

function Get-LastFmSearchCover([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }

    $resultLink = [regex]::Match($Html, 'href=["'']/music/[^"''#?]+/_/[^"''#?]+["'']', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $areas = @()
    if ($resultLink.Success) {
        $start = [Math]::Max(0, $resultLink.Index - 3200)
        $length = [Math]::Min($Html.Length - $start, 9000)
        $areas += $Html.Substring($start, $length)
    }
    $areas += $Html

    $patterns = @(
        '(?:src|data-src)=["''](?<url>https://lastfm\.freetls\.fastly\.net/i/u/[^"'']+)',
        'srcset=["''][^"'']*(?<url>https://lastfm\.freetls\.fastly\.net/i/u/[^\s,"'']+)'
    )
    foreach ($area in $areas) {
        foreach ($pattern in $patterns) {
            $matches = [regex]::Matches($area, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                $candidate = Upgrade-LastFmImage $match.Groups['url'].Value
                if (Is-UsableImageUrl $candidate) { return $candidate }
            }
        }
    }
    return $null
}

function Resolve-LastFmCoverUrl {
    $queries = @()
    $queries += [pscustomobject]@{ Kind = 'tracks'; Query = ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Title)).Trim() }
    if (-not [string]::IsNullOrWhiteSpace($Album)) {
        $queries += [pscustomobject]@{ Kind = 'albums'; Query = ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Album)).Trim() }
    }

    foreach ($item in $queries) {
        if ([string]::IsNullOrWhiteSpace($item.Query)) { continue }
        try {
            $searchUrl = 'https://www.last.fm/search/' + $item.Kind + '?q=' + [Uri]::EscapeDataString($item.Query)
            $html = Invoke-Http $searchUrl

            $fast = Get-LastFmSearchCover $html
            if (-not [string]::IsNullOrWhiteSpace($fast)) { return $fast }

            $pageUrl = Get-FirstTrackPage $html
            if (-not [string]::IsNullOrWhiteSpace($pageUrl)) {
                $pageHtml = Invoke-Http $pageUrl
                $og = Get-OgImage $pageHtml
                if (-not [string]::IsNullOrWhiteSpace($og)) { return $og }
            }
        } catch {
            Write-Log "Last.fm kapak aramasi hatasi ($($item.Query)): $($_.Exception.Message)"
        }
    }
    return $null
}

function Get-SpotifyTrackUrlFromSearchHtml([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $decoded = Html-Decode $Html

    $direct = [regex]::Match($decoded, 'https://open\.spotify\.com/track/(?<id>[A-Za-z0-9]{15,30})', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($direct.Success) { return 'https://open.spotify.com/track/' + $direct.Groups['id'].Value }

    $encoded = [regex]::Match($decoded, 'https%3A%2F%2Fopen\.spotify\.com%2Ftrack%2F(?<id>[A-Za-z0-9]{15,30})', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($encoded.Success) { return 'https://open.spotify.com/track/' + $encoded.Groups['id'].Value }

    $uddgMatches = [regex]::Matches($decoded, 'uddg=(?<url>[^&"'']+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $uddgMatches) {
        try {
            $url = [Uri]::UnescapeDataString($match.Groups['url'].Value)
            if ($url -match '^https://open\.spotify\.com/track/[A-Za-z0-9]{15,30}') { return $Matches[0] }
        } catch {}
    }
    return $null
}

function Resolve-SpotifyCoverUrl {
    $query = ((Normalize-Text $Artist) + ' ' + (Normalize-Text $Title)).Trim()
    if ([string]::IsNullOrWhiteSpace($query)) { return $null }

    $searchQueries = @(
        'site:open.spotify.com/track "' + $Artist + '" "' + $Title + '"',
        'site:open.spotify.com/track ' + $query
    )

    foreach ($searchQuery in $searchQueries) {
        $pages = @(
            'https://www.bing.com/search?q=' + [Uri]::EscapeDataString($searchQuery),
            'https://html.duckduckgo.com/html/?q=' + [Uri]::EscapeDataString($searchQuery)
        )
        foreach ($searchUrl in $pages) {
            try {
                $searchHtml = Invoke-Http $searchUrl
                $trackUrl = Get-SpotifyTrackUrlFromSearchHtml $searchHtml
                if ([string]::IsNullOrWhiteSpace($trackUrl)) { continue }

                $trackIdMatch = [regex]::Match($trackUrl, '/track/(?<id>[A-Za-z0-9]{15,30})', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if (-not $trackIdMatch.Success) { continue }
                $trackId = $trackIdMatch.Groups['id'].Value

                # Embed sayfasi daha kucuk ve OpenGraph kapagi daha tutarli.
                $spotifyHtml = Invoke-Http ('https://open.spotify.com/embed/track/' + $trackId)
                $image = Get-OgImage $spotifyHtml
                if (-not [string]::IsNullOrWhiteSpace($image)) { return $image }

                $spotifyHtml = Invoke-Http ('https://open.spotify.com/track/' + $trackId)
                $image = Get-OgImage $spotifyHtml
                if (-not [string]::IsNullOrWhiteSpace($image)) { return $image }
            } catch {
                Write-Log "Spotify web kapak aramasi hatasi: $($_.Exception.Message)"
            }
        }
    }
    return $null
}

function Resolve-CoverUrl {
    # Deezer'in herkese acik API'si ana kaynaktir ve API anahtari gerektirmez.
    $url = Resolve-DeezerCoverUrl
    if (-not [string]::IsNullOrWhiteSpace($url)) { return $url }

    # Deezer'da sonuc yoksa iTunes Search API'ye dus.
    $url = Resolve-ITunesCoverUrl
    if (-not [string]::IsNullOrWhiteSpace($url)) { return $url }

    # API kaynaklarinda sonuc yoksa mevcut web kaynaklarina dus.
    $url = Resolve-LastFmCoverUrl
    if (-not [string]::IsNullOrWhiteSpace($url)) { return $url }

    # Last.fm'de kapak yoksa Spotify'nin herkese acik web sayfasina dus.
    $url = Resolve-SpotifyCoverUrl
    if (-not [string]::IsNullOrWhiteSpace($url)) { return $url }

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

$key = Get-SafeTrackKey $Artist $Title $Album
$fetchingPath = Join-Path $CoverRoot ($key + '.fetching')
$failedPath = Join-Path $CoverRoot ($key + '.failed')

try {
    $imageUrl = Resolve-CoverUrl
    if ([string]::IsNullOrWhiteSpace($imageUrl)) { throw 'Album kapagi URL bulunamadi.' }

    $image = Invoke-Http $imageUrl $true
    if ($null -eq $image -or $null -eq $image.Bytes -or $image.Bytes.Length -lt 1024) { throw 'Album kapagi indirilemedi.' }

    foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp')) {
        Remove-Item -LiteralPath (Join-Path $CoverRoot ($key + $ext)) -Force -ErrorAction SilentlyContinue
    }

    $extension = Get-ImageExtension $image.Bytes $image.ContentType
    $targetPath = Join-Path $CoverRoot ($key + $extension)
    $tempPath = $targetPath + '.tmp'
    [IO.File]::WriteAllBytes($tempPath, $image.Bytes)
    Move-Item -LiteralPath $tempPath -Destination $targetPath -Force
    Remove-Item -LiteralPath $failedPath -Force -ErrorAction SilentlyContinue
    Write-Log "Album kapagi cache'e alindi: $Artist - $Title"
} catch {
    try { Set-Content -LiteralPath $failedPath -Value $_.Exception.Message -Encoding UTF8 } catch {}
    Write-Log "Album kapagi indirilemedi ($Artist - $Title): $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item -LiteralPath $fetchingPath -Force -ErrorAction SilentlyContinue
}
