#requires -Version 5.1
# Pester 5. The tray kit draws at the tray's size, keeps its alpha, and every tool's colour reads on
# a light and a dark taskbar.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\FleetTray.ps1')
    if (-not (Import-FleetTrayArt)) { throw 'FleetTrayArt.cs did not compile.' }
}

Describe 'Tray size' {
    It 'follows the display scale: 16 px at 100 %, 20 at 125 %, 24 at 150 %, 32 at 200 %' {
        [FleetTray.Art]::SizeForDpi(96) | Should -Be 16
        [FleetTray.Art]::SizeForDpi(120) | Should -Be 20
        [FleetTray.Art]::SizeForDpi(144) | Should -Be 24
        [FleetTray.Art]::SizeForDpi(168) | Should -Be 28
        [FleetTray.Art]::SizeForDpi(192) | Should -Be 32
        [FleetTray.Art]::SizeForDpi(0) | Should -Be 16
    }
    It 'reads this display' {
        Get-FleetTraySize | Should -BeGreaterOrEqual 16
    }
}

Describe 'Icons' {
    It 'are exactly the size asked for, with transparent corners and an opaque middle' {
        foreach ($size in 16, 20, 24, 32) {
            $icon = Get-FleetTrayIcon -App lazarette -Size $size
            $icon.Width | Should -Be $size
            $bmp = $icon.ToBitmap()
            $bmp.GetPixel(0, 0).A | Should -BeLessThan 40
            $bmp.GetPixel([int]($size / 2), 2).A | Should -Be 255
            $bmp.Dispose(); $icon.Dispose()
        }
    }
    It 'keep soft edges (partly transparent pixels), which GetHicon would lose' {
        $bmp = (Get-FleetTrayIcon -App fairlead -Size 24).ToBitmap()
        $soft = 0
        for ($x = 0; $x -lt 24; $x++) { for ($y = 0; $y -lt 24; $y++) { $a = $bmp.GetPixel($x, $y).A; if ($a -gt 0 -and $a -lt 255) { $soft++ } } }
        $soft | Should -BeGreaterThan 4
    }
    It 'draw a status badge in the corner' {
        $plain = (Get-FleetTrayIcon -App capstan -Size 16).ToBitmap().GetPixel(13, 13)
        $bad = (Get-FleetTrayIcon -App capstan -Status bad -Size 16).ToBitmap().GetPixel(13, 13)
        $bad.ToArgb() | Should -Not -Be $plain.ToArgb()
        $bad.R | Should -BeGreaterThan 180
    }
    It 'draw a status dot' {
        $dot = Get-FleetTrayDot -Status busy -Size 20
        $dot.Width | Should -Be 20
        $dot.ToBitmap().GetPixel(10, 10).ToArgb() | Should -Be ([FleetTray.Art]::Busy.ToArgb())
    }
    It 'fall back to the tool''s .ico at the right size when asked for one that is not drawn' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('fleettray-' + [guid]::NewGuid() + '.ico')
        try {
            Export-FleetTrayIco -App windlass -Path $tmp
            (Get-FleetTrayFallback -Path $tmp -Size 24).Width | Should -Be 24
            (Get-FleetTrayFallback -Path 'C:\nope.ico' -Size 24) | Should -Be ([System.Drawing.SystemIcons]::Application)
        } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }
}

Describe 'Colours' {
    It 'every tool''s tile stands out from both taskbars, and its letter from the tile' {
        foreach ($app in [FleetTray.Art]::KnownApps()) {
            $bmp = [FleetTray.Art]::DrawApp($app, '', 32)
            $fill = $bmp.GetPixel(16, 3)
            [FleetTray.Art]::Score($fill) | Should -BeGreaterOrEqual 2.0 -Because $app
            [FleetTray.Art]::Contrast($fill, [FleetTray.Art]::InkFor($fill)) | Should -BeGreaterOrEqual 4.5 -Because $app
            $bmp.Dispose()
        }
    }
}

Describe '.ico export' {
    It 'writes every size from 16 to 256 px' {
        $bytes = [FleetTray.Art]::AppIcoBytes('lazarette')
        [BitConverter]::ToUInt16($bytes, 4) | Should -Be 9
    }
}

Describe 'Source rules' {
    It 'uses no P/Invoke, no network and no GetHicon, so every tool can carry it' {
        $src = Get-Content (Join-Path $PSScriptRoot '..\FleetTrayArt.cs') -Raw
        $src | Should -Not -Match 'DllImport|System\.Net|GetHicon\(|Process\.Start|https?://'
    }
}
