# OBS Now Playing Widget
# Windows 10/11 yerel medya oturumunu okur. Spotify/Web API, OAuth veya token kullanmaz.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath = Join-Path $Root 'log.txt'
$PidPath = Join-Path $Root 'widget.pid'
$ConfigPath = Join-Path $Root 'config.json'
$WebRoot = Join-Path $Root 'wwwroot'
$ArtistRoot = Join-Path $Root 'artists'
$CoverRoot = Join-Path $Root 'covers'
$ArtistFetcherPath = Join-Path $Root 'fetch-artist.ps1'
$CoverFetcherPath = Join-Path $Root 'fetch-cover.ps1'
$MediaEventBridgePath = Join-Path $Root 'OBSNowPlaying.MediaEvents.dll'
$listener = $null

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Get-UnixMilliseconds {
    return [int64](([DateTime]::UtcNow - [DateTime]::SpecifyKind([DateTime]'1970-01-01', [DateTimeKind]::Utc)).TotalMilliseconds)
}

function Normalize-Text([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

try {
    Set-Content -Path $PidPath -Value $PID -Encoding ASCII
    Set-Content -Path $LogPath -Value '' -Encoding UTF8
    Write-Log "Baslatiliyor. PID=$PID"

    if (-not (Test-Path $ConfigPath)) { throw 'config.json bulunamadi.' }
    if (-not (Test-Path -LiteralPath $ArtistRoot -PathType Container)) { New-Item -ItemType Directory -Path $ArtistRoot -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $CoverRoot -PathType Container)) { New-Item -ItemType Directory -Path $CoverRoot -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $ArtistFetcherPath -PathType Leaf)) { throw 'fetch-artist.ps1 bulunamadi.' }
    if (-not (Test-Path -LiteralPath $CoverFetcherPath -PathType Leaf)) { throw 'fetch-cover.ps1 bulunamadi.' }
    $Config = Get-Content -Raw -Path $ConfigPath -Encoding UTF8 | ConvertFrom-Json
    $Port = [int]$Config.port
    $PollIntervalMs = [Math]::Max(100, [int]$Config.pollIntervalMs)
    $PreferredPlayers = @($Config.preferredPlayers | ForEach-Object { [string]$_ })
    $OnlyPreferredPlayers = [bool]$Config.onlyPreferredPlayers
    $AutoFetchArtistImages = $true
    if ($null -ne $Config.PSObject.Properties['autoFetchArtistImages']) { $AutoFetchArtistImages = [bool]$Config.autoFetchArtistImages }
    $AutoFetchCoverImages = $true
    if ($null -ne $Config.PSObject.Properties['autoFetchCoverImages']) { $AutoFetchCoverImages = [bool]$Config.autoFetchCoverImages }

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType=WindowsRuntime]

    $script:EventBridge = $null
    if (Test-Path -LiteralPath $MediaEventBridgePath -PathType Leaf) {
        try {
            Add-Type -Path $MediaEventBridgePath
            $script:EventBridge = New-Object ObsMediaEventBridge
            Write-Log 'WinRT medya olay koprusu yuklendi.'
        } catch { Write-Log "WinRT medya olay koprusu yuklenemedi; saglik kontrolu kullanilacak: $($_.Exception.Message)" }
    } else {
        Write-Log 'WinRT medya olay koprusu bulunamadi; saglik kontrolu kullanilacak.'
    }

    $script:AsTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } |
        Select-Object -First 1

    if ($null -eq $script:AsTaskMethod) { throw 'WinRT AsTask yardimcisi bulunamadi.' }

    function Await-WinRT([object]$AsyncOperation, [Type]$ResultType) {
        $method = $script:AsTaskMethod.MakeGenericMethod($ResultType)
        $task = $method.Invoke($null, @($AsyncOperation))
        return $task.GetAwaiter().GetResult()
    }

    function Get-PreferenceRank([string]$SourceId) {
        for ($i = 0; $i -lt $PreferredPlayers.Count; $i++) {
            if ($SourceId.IndexOf($PreferredPlayers[$i], [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $i
            }
        }
        return 9999
    }

    function Get-SourceLabel([string]$SourceId) {
        $id = $SourceId.ToLowerInvariant()
        if ($id.Contains('spotify')) { return 'Spotify' }
        if ($id.Contains('applemusic') -or $id.Contains('appleinc.applemusic') -or $id.Contains('itunes')) { return 'Apple Music' }
        if ($id.Contains('youtube music') -or $id.Contains('youtubemusic') -or $id.Contains('youtube_music') -or $id.Contains('ytmd') -or $id.Contains('th-ch.youtube-music')) { return 'YouTube Music' }
        if ($id.Contains('deezer')) { return 'Deezer' }
        if ($id.Contains('msedge')) { return 'Microsoft Edge' }
        if ($id.Contains('chrome')) { return 'Google Chrome' }
        if ($id.Contains('firefox')) { return 'Firefox' }
        if ($id.Contains('vlc')) { return 'VLC' }
        if ($id.Contains('foobar')) { return 'foobar2000' }
        if ($id.Contains('musicbee')) { return 'MusicBee' }
        if ([string]::IsNullOrWhiteSpace($SourceId)) { return 'Muzik' }
        $name = [IO.Path]::GetFileNameWithoutExtension($SourceId)
        if ([string]::IsNullOrWhiteSpace($name)) { return $SourceId }
        return $name
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
        $value = Remove-Diacritics (Normalize-Text $Text).ToLowerInvariant()
        $value = [regex]::Replace($value, '[^a-z0-9]+', '-')
        return $value.Trim('-')
    }

    function ConvertTo-Base64Text([string]$Text) {
        if ($null -eq $Text) { $Text = '' }
        return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
    }

    function Get-SafeTrackKey([string]$Artist, [string]$Title, [string]$Album) {
        $raw = ((Normalize-Text $Artist).ToLowerInvariant() + '|' + (Normalize-Text $Title).ToLowerInvariant() + '|' + (Normalize-Text $Album).ToLowerInvariant())
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
            return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
    }

    function Find-CachedCoverImagePath([string]$Artist, [string]$Title, [string]$Album) {
        if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
        $key = Get-SafeTrackKey $Artist $Title $Album
        foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp')) {
            $candidate = Join-Path $CoverRoot ($key + $ext)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
        return $null
    }

    function Read-CachedImage([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        try {
            $bytes = [IO.File]::ReadAllBytes($Path)
            if ($bytes.Length -lt 256) { return $null }
            return [pscustomobject]@{
                Bytes = $bytes
                ContentType = Detect-ImageContentType $bytes ''
            }
        } catch {
            Write-Log "Onbellek resmi okunamadi ($Path): $($_.Exception.Message)"
            return $null
        }
    }

    function Start-CoverImageFetch([string]$Artist, [string]$Title, [string]$Album) {
        if (-not $AutoFetchCoverImages -or [string]::IsNullOrWhiteSpace($Title)) { return }
        if (-not (Test-Path -LiteralPath $CoverFetcherPath -PathType Leaf)) { return }
        if ($null -ne (Find-CachedCoverImagePath $Artist $Title $Album)) { return }

        $key = Get-SafeTrackKey $Artist $Title $Album
        $fetchingPath = Join-Path $CoverRoot ($key + '.fetching')
        $failedPath = Join-Path $CoverRoot ($key + '.failed')

        if (Test-Path -LiteralPath $fetchingPath -PathType Leaf) {
            try {
                $age = (Get-Date) - (Get-Item -LiteralPath $fetchingPath).LastWriteTime
                if ($age.TotalSeconds -lt 25) { return }
                Remove-Item -LiteralPath $fetchingPath -Force -ErrorAction SilentlyContinue
            } catch { return }
        }

        if (Test-Path -LiteralPath $failedPath -PathType Leaf) {
            try {
                $age = (Get-Date) - (Get-Item -LiteralPath $failedPath).LastWriteTime
                if ($age.TotalSeconds -lt 15) { return }
                Remove-Item -LiteralPath $failedPath -Force -ErrorAction SilentlyContinue
            } catch {}
        }

        try {
            Set-Content -LiteralPath $fetchingPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII
            $artist64 = ConvertTo-Base64Text $Artist
            $title64 = ConvertTo-Base64Text $Title
            $album64 = ConvertTo-Base64Text $Album
            $root64 = ConvertTo-Base64Text $CoverRoot
            $log64 = ConvertTo-Base64Text $LogPath
            $fetcherEscaped = $CoverFetcherPath.Replace("'", "''")
            $command = "& '$fetcherEscaped' -ArtistBase64 '$artist64' -TitleBase64 '$title64' -AlbumBase64 '$album64' -CoverRootBase64 '$root64' -LogPathBase64 '$log64'"
            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-EncodedCommand',$encodedCommand) -WindowStyle Hidden | Out-Null
        } catch {
            Remove-Item -LiteralPath $fetchingPath -Force -ErrorAction SilentlyContinue
            Write-Log "Kapak arka plan islemi baslatilamadi ($Artist - $Title): $($_.Exception.Message)"
        }
    }

    function Find-CachedArtistImagePath([string]$ArtistName) {
        if ([string]::IsNullOrWhiteSpace($ArtistName)) { return $null }
        $key = Get-SafeArtistKey $ArtistName
        if ([string]::IsNullOrWhiteSpace($key)) { return $null }
        foreach ($ext in @('.png', '.jpg', '.jpeg', '.webp')) {
            $candidate = Join-Path $ArtistRoot ($key + $ext)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
        return $null
    }

    function Start-ArtistImageFetch([string]$ArtistName) {
        if (-not $AutoFetchArtistImages -or [string]::IsNullOrWhiteSpace($ArtistName)) { return }
        if (-not (Test-Path -LiteralPath $ArtistFetcherPath -PathType Leaf)) { return }
        if ($null -ne (Find-CachedArtistImagePath $ArtistName)) { return }

        $key = Get-SafeArtistKey $ArtistName
        if ([string]::IsNullOrWhiteSpace($key)) { return }
        $fetchingPath = Join-Path $ArtistRoot ($key + '.fetching')
        $failedPath = Join-Path $ArtistRoot ($key + '.failed')

        if (Test-Path -LiteralPath $fetchingPath -PathType Leaf) {
            try {
                $age = (Get-Date) - (Get-Item -LiteralPath $fetchingPath).LastWriteTime
                if ($age.TotalSeconds -lt 30) { return }
                Remove-Item -LiteralPath $fetchingPath -Force -ErrorAction SilentlyContinue
            } catch { return }
        }

        if (Test-Path -LiteralPath $failedPath -PathType Leaf) {
            try {
                $age = (Get-Date) - (Get-Item -LiteralPath $failedPath).LastWriteTime
                if ($age.TotalMinutes -lt 10) { return }
                Remove-Item -LiteralPath $failedPath -Force -ErrorAction SilentlyContinue
            } catch {}
        }

        try {
            Set-Content -LiteralPath $fetchingPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII
            $artist64 = ConvertTo-Base64Text $ArtistName
            $root64 = ConvertTo-Base64Text $ArtistRoot
            $log64 = ConvertTo-Base64Text $LogPath
            $fetcherEscaped = $ArtistFetcherPath.Replace("'", "''")
            $command = "& '$fetcherEscaped' -ArtistBase64 '$artist64' -ArtistRootBase64 '$root64' -LogPathBase64 '$log64'"
            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-EncodedCommand',$encodedCommand) -WindowStyle Hidden | Out-Null
        } catch {
            Remove-Item -LiteralPath $fetchingPath -Force -ErrorAction SilentlyContinue
            Write-Log "Sanatci gorseli arka plan islemi baslatilamadi ($ArtistName): $($_.Exception.Message)"
        }
    }

    function Detect-ImageContentType([byte[]]$Bytes, [string]$Reported) {
        if (-not [string]::IsNullOrWhiteSpace($Reported) -and $Reported.StartsWith('image/')) { return $Reported }
        if ($Bytes.Length -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return 'image/png' }
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return 'image/jpeg' }
        if ($Bytes.Length -ge 12 -and [Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($Bytes, 8, 4) -eq 'WEBP') { return 'image/webp' }
        return 'image/jpeg'
    }

    function Read-Thumbnail([object]$Thumbnail) {
        if ($null -eq $Thumbnail) { return $null }
        $randomStream = $null
        $reader = $null
        try {
            $randomStream = Await-WinRT ($Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
            $maxBytes = [uint64](8 * 1024 * 1024)
            $streamSize = [uint64]$randomStream.Size
            if ($streamSize -eq 0) { return $null }
            if ($streamSize -gt $maxBytes) { $streamSize = $maxBytes }
            $size = [uint32]$streamSize
            $inputStream = $randomStream.GetInputStreamAt(0)
            $reader = [Windows.Storage.Streams.DataReader]::new($inputStream)
            $loaded = Await-WinRT ($reader.LoadAsync($size)) ([UInt32])
            if ($loaded -eq 0) { return $null }
            $bytes = New-Object byte[] ([int]$loaded)
            $reader.ReadBytes($bytes)
            return [pscustomobject]@{
                Bytes = $bytes
                ContentType = Detect-ImageContentType $bytes ([string]$randomStream.ContentType)
            }
        } catch {
            Write-Log "Kapak resmi okunamadi: $($_.Exception.Message)"
            return $null
        } finally {
            if ($null -ne $reader) { try { $reader.Dispose() } catch {} }
            if ($null -ne $randomStream) { try { $randomStream.Dispose() } catch {} }
        }
    }

    $script:Manager = $null
    $script:CurrentSession = $null
    $script:ManagerEventsRegistered = $false
    $script:SessionEventsRegistered = $false
    $script:CurrentTrackKey = ''
    $script:CoverBytes = $null
    $script:CoverContentType = 'image/jpeg'
    $script:CoverVersion = 0
    $script:State = [ordered]@{
        connected = $false
        hasMedia = $false
        title = ''
        artist = ''
        album = ''
        source = ''
        sourceId = ''
        status = 'Closed'
        isPlaying = $false
        positionMs = 0
        durationMs = 0
        playbackRate = 1.0
        coverVersion = 0
        updatedAt = Get-UnixMilliseconds
        error = ''
        controls = [ordered]@{ previous = $false; toggle = $false; next = $false }
    }

    function Unregister-MediaEvents([bool]$IncludeManager = $false) {
        if ($null -eq $script:EventBridge) { return }
        try { $script:EventBridge.DetachSession() } catch {}
        $script:SessionEventsRegistered = $false
        if ($IncludeManager) {
            try { $script:EventBridge.DetachManager() } catch {}
            $script:ManagerEventsRegistered = $false
        }
    }

    function Register-ManagerEvents {
        if ($null -eq $script:EventBridge -or $null -eq $script:Manager -or $script:ManagerEventsRegistered) { return }
        try {
            $script:EventBridge.AttachManager($script:Manager)
            $script:ManagerEventsRegistered = $true
            Write-Log 'Medya yoneticisi olay abonelikleri etkinlestirildi.'
        } catch {
            Unregister-MediaEvents $true
            Write-Log "Medya yoneticisi olay aboneligi kurulamadi; saglik kontrolu kullanilacak: $($_.Exception.Message)"
        }
    }

    function Sync-MediaSessionEvents {
        if ($null -eq $script:CurrentSession) {
            Unregister-MediaEvents $false
            return
        }
        if ($null -eq $script:EventBridge) { return }
        if ($script:EventBridge.IsAttachedTo($script:CurrentSession)) { return }

        Unregister-MediaEvents $false
        try {
            $script:EventBridge.AttachSession($script:CurrentSession)
            $script:SessionEventsRegistered = $true
            Write-Log "Medya olay abonelikleri etkinlestirildi: $($script:State.sourceId)"
        } catch {
            Unregister-MediaEvents $false
            Write-Log "Medya olay aboneligi kurulamadi; saglik kontrolu kullanilacak: $($_.Exception.Message)"
        }
    }

    function Test-AndClearMediaEvents {
        if ($null -eq $script:EventBridge) { return $false }
        try { return [bool]$script:EventBridge.Consume() }
        catch { return $false }
    }

    function Ensure-Manager {
        if ($null -ne $script:Manager) { return $true }
        try {
            $script:Manager = Await-WinRT ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
            Register-ManagerEvents
            Write-Log 'Windows medya oturumu baglantisi kuruldu.'
            return $true
        } catch {
            $script:State.connected = $false
            $script:State.error = "Windows medya oturumuna erisilemiyor: $($_.Exception.Message)"
            Write-Log $script:State.error
            return $false
        }
    }

    function Select-MediaSession {
        $sessions = @($script:Manager.GetSessions())
        if ($sessions.Count -eq 0) { return $null }

        $candidates = @()
        foreach ($session in $sessions) {
            try {
                $sourceId = Normalize-Text $session.SourceAppUserModelId
                $rank = Get-PreferenceRank $sourceId
                if ($OnlyPreferredPlayers -and $rank -ge 9999) { continue }
                $info = $session.GetPlaybackInfo()
                $isPlaying = ([string]$info.PlaybackStatus -eq 'Playing')
                $candidates += [pscustomobject]@{ Session = $session; Rank = $rank; Playing = $isPlaying; SourceId = $sourceId }
            } catch {}
        }
        if ($candidates.Count -eq 0) { return $null }

        $playing = @($candidates | Where-Object { $_.Playing } | Sort-Object Rank)
        if ($playing.Count -gt 0) { return $playing[0].Session }

        try {
            $current = $script:Manager.GetCurrentSession()
            if ($null -ne $current) {
                $currentId = Normalize-Text $current.SourceAppUserModelId
                if (-not $OnlyPreferredPlayers -or (Get-PreferenceRank $currentId) -lt 9999) { return $current }
            }
        } catch {}

        return ($candidates | Sort-Object Rank | Select-Object -First 1).Session
    }

    function Reset-State([string]$ErrorText = '') {
        $script:CurrentSession = $null
        $script:CurrentTrackKey = ''
        $script:CoverBytes = $null
        $script:CoverVersion++
        $script:State.coverVersion = $script:CoverVersion
        $script:State.connected = ($null -ne $script:Manager)
        $script:State.hasMedia = $false
        $script:State.title = ''
        $script:State.artist = ''
        $script:State.album = ''
        $script:State.source = ''
        $script:State.sourceId = ''
        $script:State.status = 'Closed'
        $script:State.isPlaying = $false
        $script:State.positionMs = 0
        $script:State.durationMs = 0
        $script:State.playbackRate = 1.0
        $script:State.updatedAt = Get-UnixMilliseconds
        $script:State.error = $ErrorText
        $script:State.controls.previous = $false
        $script:State.controls.toggle = $false
        $script:State.controls.next = $false
    }

    function Update-MediaState {
        try {
            if (-not (Ensure-Manager)) { return }
            $session = Select-MediaSession
            if ($null -eq $session) {
                Reset-State
                return
            }

            $script:CurrentSession = $session
            $sourceId = Normalize-Text $session.SourceAppUserModelId
            $playback = $session.GetPlaybackInfo()
            $timeline = $session.GetTimelineProperties()
            $properties = Await-WinRT ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
            if ($null -eq $properties) { Reset-State 'Medya ozellikleri alinamadi.'; return }

            $title = Normalize-Text $properties.Title
            $artist = Normalize-Text $properties.Artist
            if ([string]::IsNullOrWhiteSpace($artist)) { $artist = Normalize-Text $properties.AlbumArtist }
            $album = Normalize-Text $properties.AlbumTitle
            $status = [string]$playback.PlaybackStatus
            $isPlaying = ($status -eq 'Playing')
            $rate = 1.0
            if ($null -ne $playback.PlaybackRate) {
                try {
                    if ($playback.PlaybackRate.HasValue) { $rate = [double]$playback.PlaybackRate.Value }
                    else { $rate = [double]$playback.PlaybackRate }
                } catch { try { $rate = [double]$playback.PlaybackRate } catch {} }
            }
            if ($rate -le 0) { $rate = 1.0 }

            $startMs = [double]$timeline.StartTime.TotalMilliseconds
            $endMs = [double]$timeline.EndTime.TotalMilliseconds
            $positionMs = [double]$timeline.Position.TotalMilliseconds - $startMs
            $durationMs = [Math]::Max(0, $endMs - $startMs)

            if ($isPlaying) {
                try {
                    $elapsedMs = ([DateTimeOffset]::UtcNow - $timeline.LastUpdatedTime).TotalMilliseconds
                    if ($elapsedMs -gt 0 -and $elapsedMs -lt 30000) { $positionMs += ($elapsedMs * $rate) }
                } catch {}
            }
            if ($positionMs -lt 0) { $positionMs = 0 }
            if ($durationMs -gt 0 -and $positionMs -gt $durationMs) { $positionMs = $durationMs }

            $trackKey = "$sourceId|$title|$artist|$album"
            $isNewTrack = ($trackKey -ne $script:CurrentTrackKey)

            if ($isNewTrack) {
                $script:CurrentTrackKey = $trackKey
                $script:CoverBytes = $null
                $script:CoverContentType = 'image/jpeg'
                $script:CoverVersion++

                Start-ArtistImageFetch $artist
                Write-Log "Parca degisti: $artist - $title [$sourceId]"
            }

            if ($null -eq $script:CoverBytes -or $script:CoverBytes.Length -eq 0) {
                # Birinci tercih: oynaticinin Windows medya oturumuna verdigi gercek kapak.
                $thumb = Read-Thumbnail $properties.Thumbnail
                if ($null -ne $thumb) {
                    $script:CoverBytes = $thumb.Bytes
                    $script:CoverContentType = $thumb.ContentType
                    $script:CoverVersion++
                    Write-Log "Kapak Windows medya oturumundan alindi: $artist - $title"
                } else {
                    # Ikinci tercih: daha once indirilen kapagi aninda cache'den kullan.
                    $cachedCoverPath = Find-CachedCoverImagePath $artist $title $album
                    if ($null -ne $cachedCoverPath) {
                        $cachedCover = Read-CachedImage $cachedCoverPath
                        if ($null -ne $cachedCover) {
                            $script:CoverBytes = $cachedCover.Bytes
                            $script:CoverContentType = $cachedCover.ContentType
                            $script:CoverVersion++
                            Write-Log "Kapak cache'den alindi: $artist - $title"
                        }
                    }

                    # Hala yoksa indirme islemini ayri PowerShell surecinde baslat; ana widget beklemez.
                    if ($null -eq $script:CoverBytes -or $script:CoverBytes.Length -eq 0) {
                        Start-CoverImageFetch $artist $title $album
                    }
                }
            }

            $controls = $playback.Controls
            $script:State.connected = $true
            $script:State.hasMedia = (-not [string]::IsNullOrWhiteSpace($title))
            $script:State.title = $title
            $script:State.artist = $artist
            $script:State.album = $album
            $script:State.source = Get-SourceLabel $sourceId
            $script:State.sourceId = $sourceId
            $script:State.status = $status
            $script:State.isPlaying = $isPlaying
            $script:State.positionMs = [int64][Math]::Round($positionMs)
            $script:State.durationMs = [int64][Math]::Round($durationMs)
            $script:State.playbackRate = $rate
            $script:State.coverVersion = $script:CoverVersion
            $script:State.updatedAt = Get-UnixMilliseconds
            $script:State.error = ''
            $script:State.controls.previous = [bool]$controls.IsPreviousEnabled
            $script:State.controls.toggle = ([bool]$controls.IsPlayEnabled -or [bool]$controls.IsPauseEnabled)
            $script:State.controls.next = [bool]$controls.IsNextEnabled
        } catch {
            $message = $_.Exception.Message
            Write-Log "Medya bilgisi hatasi: $message"
            Unregister-MediaEvents $true
            $script:Manager = $null
            Reset-State $message
        }
    }

    function Update-TimelineState {
        if ($null -eq $script:CurrentSession -or -not $script:State.hasMedia) { return }
        try {
            # Hafif guncelleme: pahali TryGetMediaPropertiesAsync cagrisini yapmaz.
            $playback = $script:CurrentSession.GetPlaybackInfo()
            $timeline = $script:CurrentSession.GetTimelineProperties()
            $status = [string]$playback.PlaybackStatus
            $isPlaying = ($status -eq 'Playing')
            $rate = 1.0
            if ($null -ne $playback.PlaybackRate) {
                try {
                    if ($playback.PlaybackRate.HasValue) { $rate = [double]$playback.PlaybackRate.Value }
                    else { $rate = [double]$playback.PlaybackRate }
                } catch { try { $rate = [double]$playback.PlaybackRate } catch {} }
            }
            if ($rate -le 0) { $rate = 1.0 }

            $startMs = [double]$timeline.StartTime.TotalMilliseconds
            $endMs = [double]$timeline.EndTime.TotalMilliseconds
            $positionMs = [double]$timeline.Position.TotalMilliseconds - $startMs
            $durationMs = [Math]::Max(0, $endMs - $startMs)
            if ($isPlaying) {
                try {
                    $elapsedMs = ([DateTimeOffset]::UtcNow - $timeline.LastUpdatedTime).TotalMilliseconds
                    if ($elapsedMs -gt 0 -and $elapsedMs -lt 30000) { $positionMs += ($elapsedMs * $rate) }
                } catch {}
            }
            if ($positionMs -lt 0) { $positionMs = 0 }
            if ($durationMs -gt 0 -and $positionMs -gt $durationMs) { $positionMs = $durationMs }

            $script:State.status = $status
            $script:State.isPlaying = $isPlaying
            $script:State.positionMs = [int64][Math]::Round($positionMs)
            $script:State.durationMs = [int64][Math]::Round($durationMs)
            $script:State.playbackRate = $rate
            $script:State.updatedAt = Get-UnixMilliseconds
        } catch {
            # Oturum kapanmissa bir sonraki dongude tam yenileme yapilmasini sagla.
            $script:NextHealthCheck = [DateTime]::MinValue
        }
    }

    function Ensure-CurrentCoverAvailable {
        if ($null -ne $script:CoverBytes -and $script:CoverBytes.Length -gt 0) { return $true }
        if (-not $script:State.hasMedia -or [string]::IsNullOrWhiteSpace($script:State.title)) { return $false }

        $cachedCoverPath = Find-CachedCoverImagePath $script:State.artist $script:State.title $script:State.album
        if ($null -ne $cachedCoverPath) {
            $cachedCover = Read-CachedImage $cachedCoverPath
            if ($null -ne $cachedCover) {
                $script:CoverBytes = $cachedCover.Bytes
                $script:CoverContentType = $cachedCover.ContentType
                $script:CoverVersion++
                $script:State.coverVersion = $script:CoverVersion
                Write-Log "Kapak HTTP isteginde cache'den alindi: $($script:State.artist) - $($script:State.title)"
                return $true
            }
        }

        Start-CoverImageFetch $script:State.artist $script:State.title $script:State.album
        return $false
    }

    function Invoke-MediaControl([string]$Action) {
        if ($null -eq $script:CurrentSession) { return $false }
        try {
            switch ($Action.ToLowerInvariant()) {
                'toggle' { return [bool](Await-WinRT ($script:CurrentSession.TryTogglePlayPauseAsync()) ([bool])) }
                'next' { return [bool](Await-WinRT ($script:CurrentSession.TrySkipNextAsync()) ([bool])) }
                'previous' { return [bool](Await-WinRT ($script:CurrentSession.TrySkipPreviousAsync()) ([bool])) }
                default { return $false }
            }
        } catch {
            Write-Log "Kontrol hatasi ($Action): $($_.Exception.Message)"
            return $false
        }
    }

    function Get-ContentType([string]$Path) {
        switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
            '.html' { return 'text/html; charset=utf-8' }
            '.css' { return 'text/css; charset=utf-8' }
            '.js' { return 'application/javascript; charset=utf-8' }
            '.svg' { return 'image/svg+xml' }
            '.png' { return 'image/png' }
            '.jpg' { return 'image/jpeg' }
            '.jpeg' { return 'image/jpeg' }
            '.webp' { return 'image/webp' }
            '.json' { return 'application/json; charset=utf-8' }
            default { return 'application/octet-stream' }
        }
    }

    function Send-Response([Net.Sockets.TcpClient]$Client, [int]$StatusCode, [string]$StatusText, [string]$ContentType, [byte[]]$Body, [string]$CacheControl = 'no-store') {
        $stream = $Client.GetStream()
        $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nCache-Control: $CacheControl`r`nConnection: close`r`nAccess-Control-Allow-Origin: *`r`nX-Content-Type-Options: nosniff`r`n`r`n"
        $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        if ($Body.Length -gt 0) { $stream.Write($Body, 0, $Body.Length) }
        $stream.Flush()
    }

    function Send-Json([Net.Sockets.TcpClient]$Client, [object]$Object, [int]$StatusCode = 200, [string]$StatusText = 'OK') {
        $json = $Object | ConvertTo-Json -Compress -Depth 8
        Send-Response $Client $StatusCode $StatusText 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($json))
    }

    function Handle-Client([Net.Sockets.TcpClient]$Client) {
        try {
            $Client.ReceiveTimeout = 2000
            $stream = $Client.GetStream()
            $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 2048, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) { return }
            while ($true) {
                $line = $reader.ReadLine()
                if ($null -eq $line -or $line.Length -eq 0) { break }
            }
            $parts = $requestLine.Split(' ')
            if ($parts.Length -lt 2) { return }
            $method = $parts[0].ToUpperInvariant()
            $rawTarget = $parts[1]
            $uri = [Uri]("http://127.0.0.1$rawTarget")
            $path = [Uri]::UnescapeDataString($uri.AbsolutePath)

            if ($method -eq 'OPTIONS') {
                Send-Response $Client 204 'No Content' 'text/plain' ([byte[]]@())
                return
            }

            if ($path -eq '/api/state') {
                Send-Json $Client $script:State
                return
            }
            if ($path -eq '/api/config') {
                try {
                    $liveConfig = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $clientConfig = [ordered]@{}
                    foreach ($property in $liveConfig.widget.PSObject.Properties) { $clientConfig[$property.Name] = $property.Value }
                    $clientConfig['language'] = if ([string]$liveConfig.language -eq 'en') { 'en' } else { 'tr' }
                    Send-Json $Client $clientConfig
                } catch {
                    $fallbackConfig = [ordered]@{}
                    foreach ($property in $Config.widget.PSObject.Properties) { $fallbackConfig[$property.Name] = $property.Value }
                    $fallbackConfig['language'] = 'tr'
                    Send-Json $Client $fallbackConfig
                }
                return
            }
            if ($path -eq '/cover') {
                if (-not (Ensure-CurrentCoverAvailable)) {
                    Send-Response $Client 404 'Not Found' 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Kapak hazirlaniyor'))
                } else {
                    Send-Response $Client 200 'OK' $script:CoverContentType $script:CoverBytes 'no-cache'
                }
                return
            }
            if ($path -eq '/artist-image') {
                $artistName = [System.Web.HttpUtility]::ParseQueryString($uri.Query).Get('name')
                $artistPath = Find-CachedArtistImagePath $artistName
                if ($null -eq $artistPath) {
                    Start-ArtistImageFetch $artistName
                    Send-Response $Client 404 'Not Found' 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Sanatci gorseli hazirlaniyor'))
                } else {
                    $artistBytes = [IO.File]::ReadAllBytes($artistPath)
                    Send-Response $Client 200 'OK' (Get-ContentType $artistPath) $artistBytes 'no-cache'
                }
                return
            }
            if ($path.StartsWith('/api/control/')) {
                $action = $path.Substring('/api/control/'.Length)
                $ok = Invoke-MediaControl $action
                Send-Json $Client ([ordered]@{ ok = $ok; action = $action })
                return
            }

            if ($path -eq '/') { $path = '/index.html' }
            $relative = $path.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
            $fullPath = [IO.Path]::GetFullPath((Join-Path $WebRoot $relative))
            $safeRoot = [IO.Path]::GetFullPath($WebRoot) + [IO.Path]::DirectorySeparatorChar
            if (-not $fullPath.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                Send-Response $Client 404 'Not Found' 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('404'))
                return
            }
            $bytes = [IO.File]::ReadAllBytes($fullPath)
            Send-Response $Client 200 'OK' (Get-ContentType $fullPath) $bytes 'no-cache'
        } catch {
            Write-Log "HTTP hatasi: $($_.Exception.Message)"
        } finally {
            try { $Client.Close() } catch {}
        }
    }

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    Write-Log "Sunucu hazir: http://127.0.0.1:$Port/"

    if ([bool]$Config.openPreviewOnStart) {
        Start-Process "http://127.0.0.1:$Port/" | Out-Null
    }

    $timelineIntervalMs = [Math]::Max(500, [Math]::Min(1000, ($PollIntervalMs * 4)))
    $script:NextHealthCheck = [DateTime]::UtcNow
    $nextTimelineUpdate = [DateTime]::UtcNow
    while ($true) {
        $now = [DateTime]::UtcNow
        $mediaEventTriggered = Test-AndClearMediaEvents
        if ($mediaEventTriggered -or $now -ge $script:NextHealthCheck) {
            Update-MediaState
            Sync-MediaSessionEvents
            $healthSeconds = if ($script:ManagerEventsRegistered -and ($script:SessionEventsRegistered -or $null -eq $script:CurrentSession)) { 5 } else { 1 }
            $script:NextHealthCheck = [DateTime]::UtcNow.AddSeconds($healthSeconds)
            $nextTimelineUpdate = [DateTime]::UtcNow.AddMilliseconds($timelineIntervalMs)
        } elseif ($now -ge $nextTimelineUpdate) {
            Update-TimelineState
            $nextTimelineUpdate = [DateTime]::UtcNow.AddMilliseconds($timelineIntervalMs)
        }
        if ($listener.Pending()) {
            Handle-Client ($listener.AcceptTcpClient())
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
} catch {
    Write-Log "KRITIK HATA: $($_.Exception.ToString())"
} finally {
    try { Unregister-MediaEvents $true } catch {}
    try { if ($null -ne $listener) { $listener.Stop() } } catch {}
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}
