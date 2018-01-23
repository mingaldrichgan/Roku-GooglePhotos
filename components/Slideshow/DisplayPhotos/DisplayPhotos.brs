
Sub init()    
    m.PrimaryImage              = m.top.findNode("PrimaryImage")
    m.SecondaryImage            = m.top.findNode("SecondaryImage")
    m.BlendedPrimaryImage       = m.top.findNode("BlendedPrimaryImage")
    m.BlendedSecondaryImage     = m.top.findNode("BlendedSecondaryImage")
    m.FadeInPrimaryAnimation    = m.top.findNode("FadeInPrimaryAnimation")
    m.FadeInSecondaryAnimation  = m.top.findNode("FadeInSecondaryAnimation")
    m.FadeForeground            = m.top.findNode("FadeForeground")
    m.FadeOutForeground         = m.top.findNode("FadeOutForeground")
    m.PauseScreen               = m.top.findNode("PauseScreen")
    m.pauseImageCount           = m.top.findNode("pauseImageCount")
    m.pauseImageDetail          = m.top.findNode("pauseImageDetail")
    m.RotationTimer             = m.top.findNode("RotationTimer")
    m.DownloadTimer             = m.top.findNode("DownloadTimer")

    m.port = CreateObject("roMessagePort")

    m.fromBrowse            = false
    m.imageLocalCacheByURL  = {}
    m.imageLocalCacheByFS   = {}
    m.imageDisplay          = []
    m.imageTracker          = -1
    m.imageOnScreen         = ""
    
    m.PrimaryImage.observeField("loadStatus","onPrimaryLoadedTrigger")
    m.SecondaryImage.observeField("loadStatus","onSecondaryLoadedTrigger")
    m.RotationTimer.observeField("fire","onRotationTigger")
    m.DownloadTimer.observeField("fire","onDownloadTigger")
    m.top.observeField("content","loadImageList")

    m.showDisplay   = RegRead("SlideshowDisplay", "Settings")
    m.showOrder     = RegRead("SlideshowOrder", "Settings")
    showDelay       = RegRead("SlideshowDelay", "Settings")
    
    'Check any Temporary settings
    if m.global.SlideshowDisplay <> "" m.showDisplay = m.global.SlideshowDisplay
    if m.global.SlideshowOrder <> "" m.showOrder = m.global.SlideshowOrder
    if m.global.SlideshowDelay <> "" showDelay = m.global.SlideshowDelay
    
    print "GooglePhotos Show Delay:   "; showDelay
    print "GooglePhotos Show Order:   "; m.showOrder
    print "GooglePhotos Show Display: "; m.showDisplay
    
    if showDelay<>invalid
        m.RotationTimer.duration = strtoi(showDelay)
        if strtoi(showDelay) > 50
            'We do this to stop the ROKU screensaver if set to 1 minute
            m.DownloadTimer.duration = 50
        else if strtoi(showDelay) > 3
            m.DownloadTimer.duration = strtoi(showDelay)-3
        else
            m.DownloadTimer.duration = 2
        end if
    else
        m.RotationTimer.duration = 5
        m.DownloadTimer.duration = 2
    end if
    
    m.RotationTimer.repeat = true
    m.DownloadTimer.repeat = true
End Sub


sub loadImageList()
    print "DisplayPhotos.brs [loadImageList]"
    
    'Copy original list since we can't change origin
    originalList = m.top.content
    
    for i = 0 to m.top.content.Count()-1
    
        if m.top.startIndex <> -1 then
            'If coming from browsing, only show in Newest-Oldest order
            nxt = 0
        else
            if m.showOrder = "Random Order" then
                'Create image display list - RANDOM
                nxt = GetRandom(originalList)
            else if m.showOrder = "Oldest to Newest"
                'Create image display list - OLD FIRST
                nxt = originalList.Count()-1
            else
                'Create image display list - NEW FIRST
                nxt = 0
            end if 
        end if
        
        m.imageDisplay.push(originalList[nxt])
        originalList.Delete(nxt)
                 
    end for
    
    'We have an image list. Start display
    onRotationTigger({})
    onDownloadTigger({})
     
    m.RotationTimer.control = "start"
    m.DownloadTimer.control = "start"
     
    'Trigger a PAUSE if photo selected
    if m.top.startIndex <> -1 then
        onKeyEvent("OK", true)
    end if
     
End Sub


Sub onRotationTigger(event as object)
    'print "DisplayPhotos.brs [onRotationTigger]";

    if m.top.startIndex <> -1 then m.fromBrowse = true

    if m.showDisplay = "Multi-Scrolling" and m.fromBrowse = false then
    
        'We only allow multi scroll if starting direct, can't come from Browse Images.
        if m.screenActive = invalid then
            m.screenActive = createObject("roSGNode", "MultiScroll")
            m.screenActive.content = m.imageDisplay
            m.top.appendChild(m.screenActive)
            m.screenActive.setFocus(true)
        end if

        m.RotationTimer.control = "stop"
        m.DownloadTimer.control = "stop"
    else
        sendNextImage()
    end if
End Sub


Sub onDownloadTigger(event as object)
    'print "DisplayPhotos.brs [onDownloadTigger]"
    
    tmpDownload = []
    
    'Download Next 5 images - Only when needed
    for i = 1 to 5
        nextID = GetNextImage(m.imageDisplay, m.imageTracker+i)
        
        if m.imageDisplay.Count()-1 >= nextID
        nextURL = m.imageDisplay[nextID].url
        
        if not m.imageLocalCacheByURL.DoesExist(nextURL) then
            tmpDownload.push(m.imageDisplay[nextID])
        end if
        
        end if
    end for
    
    if tmpDownload.Count() > 0 then
        m.cacheImageTask = createObject("roSGNode", "ImageCacher")
        m.cacheImageTask.observeField("localarray", "processDownloads")
        m.cacheImageTask.observeField("filesystem", "contolCache")
        m.cacheImageTask.remotearray = tmpDownload
        m.cacheImageTask.control = "RUN"
    end if
     
    m.keyResetTask = createObject("roSGNode", "KeyReset")
    m.keyResetTask.control = "RUN"
    
End Sub


Sub processDownloads(event as object)
    'print "DisplayPhotos.brs [processDownloads]"
    
    'Take newly downloaded images and add to our localImageStore array for tracking
    response = event.getdata()
    
    for each key in response
        tmpFS = response[key]
        
        m.imageLocalCacheByURL[key] = tmpFS
        m.imageLocalCacheByFS[tmpFS] = key
    end for
End Sub


Sub contolCache(event as object)
    'Free channel, no CASH here! -- Not funny? Ok..
    
    keepImages = 20
    
    'Control the filesystem download cache - After 'keepImages' downloads start removing
    cacheArray = event.getdata()
    if type(cacheArray) = "roArray" then
        'print "Local FileSystem Count: "; cacheArray.Count()
        if (cacheArray.Count() > keepImages) then
            for i = keepImages to cacheArray.Count()
                oldImage = cacheArray.pop()
                'print "Delete from FileSystem: "; oldImage
                DeleteFile("tmp:/"+oldImage)
                
                urlLookup = m.imageLocalCacheByFS.Lookup("tmp:/"+oldImage)
                if urlLookup<>invalid
                    'Cleanup cache
                    m.imageLocalCacheByURL.Delete(urlLookup)
                    m.imageLocalCacheByFS.Delete("tmp:/"+oldImage)
                end if
            end for
        end if
    end if
    
End Sub


Sub onPrimaryLoadedTrigger(event as object)
    if event.getdata() = "ready" then
        'Center the MarkUp Box
        markupRectAlbum = m.PrimaryImage.localBoundingRect()
        centerx = (1920 - markupRectAlbum.width) / 2
        centery = (1080 - markupRectAlbum.height) / 2

        m.PrimaryImage.translation = [ centerx, centery ]
        
        'Controls the image fading
        rxFade = CreateObject("roRegex", "NoFading", "i")        
        if rxFade.IsMatch(m.showDisplay) or rxFade.IsMatch(m.imageOnScreen) then
            m.BlendedPrimaryImage.visible       = true
            m.BlendedSecondaryImage.visible     = false
            m.PrimaryImage.visible              = true
            m.SecondaryImage.visible            = false
            m.BlendedPrimaryImage.opacity       = 1
            m.PrimaryImage.opacity              = 1
            m.FadeForeground.opacity            = 0
        else
            m.BlendedPrimaryImage.visible       = true
            m.PrimaryImage.visible              = true
            m.FadeInPrimaryAnimation.control    = "start"
            
            if m.FadeForeground.opacity = 1 then
                m.FadeOutForeground.control     = "start"
            end if
            
        end if
    end if  
End Sub


Sub onSecondaryLoadedTrigger(event as object)
    if event.getdata() = "ready" then
        'Center the MarkUp Box
        markupRectAlbum = m.SecondaryImage.localBoundingRect()
        centerx = (1920 - markupRectAlbum.width) / 2
        centery = (1080 - markupRectAlbum.height) / 2

        m.SecondaryImage.translation = [ centerx, centery ]

        'Controls the image fading
        rxFade = CreateObject("roRegex", "NoFading", "i")       
        if rxFade.IsMatch(m.showDisplay) or rxFade.IsMatch(m.imageOnScreen) then
            m.BlendedPrimaryImage.visible       = false
            m.BlendedSecondaryImage.visible     = true
            m.PrimaryImage.visible              = false
            m.SecondaryImage.visible            = true
            m.BlendedSecondaryImage.opacity     = 1
            m.SecondaryImage.opacity            = 1
        else
            m.BlendedSecondaryImage.visible     = true
            m.SecondaryImage.visible            = true
            m.FadeInSecondaryAnimation.control  = "start"
        end if
    end if  
End Sub


Sub sendNextImage(direction=invalid)
    print "DisplayPhotos.brs [sendNextImage]"
        
    'Get next image to display.
    if m.top.startIndex <> -1 then
        nextID = m.top.startIndex
        m.top.startIndex = -1
    else
        if direction<>invalid and direction = "previous"
            nextID = GetPreviousImage(m.imageDisplay, m.imageTracker)
        else
            nextID = GetNextImage(m.imageDisplay, m.imageTracker)
        end if
    end if
    
    m.imageTracker = nextID
    
    url = m.imageDisplay[nextID].url
    
    'Pull image from downloaded cache if avalable
    if m.imageLocalCacheByURL.DoesExist(url) then
        url = m.imageLocalCacheByURL[url]
    end if
    
    print "Next Image: "; url
    
    'Controls the background blur
    rxBlur = CreateObject("roRegex", "YesBlur", "i")
    
    ' Whats going on here:
    '   If a direction button is pressed (previous or next) we disable fading for a better user experiance.
    '   Since the images trigger on "loadstatus" change, we first set the URI to null, then populate.
    if direction<>invalid
        if m.imageOnScreen = "PrimaryImage" or m.imageOnScreen = "PrimaryImage_NoFading" then
            m.SecondaryImage.uri = ""
            m.SecondaryImage.uri = url
            m.imageOnScreen      = "SecondaryImage_NoFading"
            if m.showDisplay = invalid or rxBlur.IsMatch(m.showDisplay) then m.BlendedSecondaryImage.uri = url
        else
            m.PrimaryImage.uri   = ""
            m.PrimaryImage.uri   = url
            m.imageOnScreen      = "PrimaryImage_NoFading"
            if m.showDisplay = invalid or rxBlur.IsMatch(m.showDisplay) then m.BlendedPrimaryImage.uri = url
        end if
    else
        if m.imageOnScreen = "PrimaryImage" or m.imageOnScreen = "PrimaryImage_NoFading" then
            m.SecondaryImage.uri = url
            m.imageOnScreen      = "SecondaryImage"
            if m.showDisplay     = invalid or rxBlur.IsMatch(m.showDisplay) then m.BlendedSecondaryImage.uri = url
        else
            m.PrimaryImage.uri   = url
            m.imageOnScreen      = "PrimaryImage"
            if m.showDisplay = invalid or rxBlur.IsMatch(m.showDisplay) then m.BlendedPrimaryImage.uri = url
        end if
    end if
    
    m.pauseImageCount.text  = itostr(nextID+1)+" of "+itostr(m.imageDisplay.Count())
    m.pauseImageDetail.text = friendlyDate(strtoi(m.imageDisplay[nextID].timestamp))
    
    'Stop rotating if only 1 image album
    if m.imageDisplay.Count() = 1 then
        m.RotationTimer.control = "stop"
        m.DownloadTimer.control = "stop"
    end if
End Sub


Function GetRandom(items As Object)
    return Rnd(items.Count())-1
End Function


Function GetNextImage(items As Object, tracker As Integer)
    if items.Count()-1 = tracker then
        return 0
    else
        return tracker + 1
    end if
End Function


Function GetPreviousImage(items As Object, tracker As Integer)
    if tracker = 0 then
        return 0
    else
        return tracker - 1
    end if
End Function


Function onKeyEvent(key as String, press as Boolean) as Boolean
    if press then
        print "KEY: "; key
        if key = "right" or key = "fastforward"
            print "RIGHT"
            sendNextImage("next")
            onDownloadTigger({})
            m.RotationTimer.control = "stop"
            m.DownloadTimer.control = "stop"
            m.PauseScreen.visible   = "true"
            return true
        else if key = "left" or key = "rewind"
            print "LEFT"
            sendNextImage("previous")
            m.RotationTimer.control = "stop"
            m.DownloadTimer.control = "stop"
            m.PauseScreen.visible   = "true"
            return true
        else if (key = "play" or key = "OK") and m.RotationTimer.control = "start"
            print "PAUSE"
            m.RotationTimer.control = "stop"
            m.DownloadTimer.control = "stop"
            m.PauseScreen.visible   = "true"
            return true
        else if (key = "play" or key = "OK") and m.RotationTimer.control = "stop"
            print "PLAY"
            sendNextImage()
            m.RotationTimer.control = "start"
            m.DownloadTimer.control = "start"
            m.PauseScreen.visible   = "false"
            return true
        else if ((key = "up") or (key = "down")) and m.PauseScreen.visible = false
            print "OPTIONS - SHOW"
            m.PauseScreen.visible   = "true"
            return true
        else if ((key = "up") or (key = "down")) and m.PauseScreen.visible = true
            print "OPTIONS - HIDE"
            m.PauseScreen.visible   = "false"
            return true
        end if
    end if

    'If nothing above is true, we'll fall back to the previous screen.
    return false
End Function