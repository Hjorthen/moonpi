create_moonlight_user:
  user.present:
  - name: moonlight
  - createhome: True
  - password_lock: True
  - shell: /usr/sbin/nologin
  - groups: [audio, video, input, render]


/etc/systemd/system/controller-connected.service:
  file.managed:
  - mode: 644
  - contents: |
      [Unit]
      Description=Controller connected
      Wants=controller-active.target
      # Stop the timeout timer if it has been enabled
      After=controller-active-timeout.timer
      Conflicts=controller-active-timeout.timer
      # If the controller stops, so should we
      StopPropagatedFrom=dev-input-gamecontroller.device
      After=dev-input-gamecontroller.device
      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/bin/true
      # Start a timeout to stop the controller-active.target
      ExecStop=/bin/systemctl start controller-active-timeout.timer

/etc/systemd/system/controller-active-timeout.timer:
  file.managed:
  - mode: 644
  - contents: |
     [Unit]
     Description=Stop the controller-active target after a delay
     [Timer]
     OnActiveSec=10s
     AccuracySec=2s
     RemainAfterElapse=no

/etc/systemd/system/controller-active-timeout.service:
  file.managed:
  - mode: 644
  - contents: |
     [Unit]
     Description=Stop the controller-active target after a delay
     [Service]
     Type=oneshot
     RemainAfterExit=no
     ExecStart=/bin/systemctl stop controller-active.target

/etc/systemd/system/controller-active.target:
  file.managed:
  - mode: 644
  - contents: |
     [Unit]
     Description=Controller currently or recently connected

/etc/udev/rules.d/99-controller-target.rules:
  file.managed:
  - mode: 644
  - contents: | 
      ACTION=="add", ATTRS{name}=="8BitDo Ultimate 2 Wireless Controller", KERNEL=="event[0-9]*", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/input/gamecontroller", ENV{SYSTEMD_WANTS}="controller-connected.service"

/etc/moonlight/eglfs.json:
  file.managed:
  - mode: 644
  - makedirs: True
  - contents: |
      {
      "device": "/dev/dri/card1",
      "outputs" : [
              {
                      "name" : "HDMI1",
                      "mode" : "1920x1080@60"
              },
              {
                      "name" : "HDMI2",
                      "mode" : "1920x1080@60"
              }
       ]
      }

/etc/systemd/system/moonlight.service:
  file.managed:
  - mode: 644
  - contents: |
      [Unit]
      Description=Moonlight
      [Service]
      User=moonlight
      Environment="STREAM_FPS=60"
      # Bitrate of stream in kbps, default seems to be 40000
      Environment=STREAM_BITRATE=20000
      Environment=SUNSHINE_IP=192.168.1.27
      Environment="QT_QPA_EGLFS_KMS_CONFIG=/etc/moonlight/eglfs.json"
      Environment="SDL_HINT_VIDEO_DOUBLE_BUFFER=1"
      # Check the KMS config exists
      ExecStartPre=test -f $QT_QPA_EGLFS_KMS_CONFIG
      ExecStart=moonlight-qt --1440 --bitrate $STREAM_BITRATE  --fps $STREAM_FPS --performance-overlay --video-codec HEVC stream $SUNSHINE_IP "Desktop"
      # We want to restart unless the process is stopped explicitly by systemd.
      Restart=always
      RestartSec=30s

/usr/local/lib/moonlight-autolauncher/restore-tty.sh:
  file.managed:
  - makedirs: True
  - mode: 744
  - contents: |
      #!/bin/sh
      PREV_TTY=`sed -nE 's/.*([0-9]+).*/\1/p' /run/moonlight-autolaunch-previous-tty`
      echo "Switching back to tty$PREV_TTY"
      chvt $PREV_TTY
      rm /run/moonlight-autolaunch-previous-tty

/usr/local/lib/moonlight-autolauncher/switch-tty.sh:
  file.managed:
  - makedirs: True
  - mode: 744
  - contents: |
      #!/bin/sh
      cp /sys/class/tty/tty0/active /run/moonlight-autolaunch-previous-tty 
      chvt 4

/etc/systemd/system/moonlight-autolauncher.service:
  file.managed:
  - mode: 644
  - contents: |
      [Unit]
      Description=Keeps Moonshine launched as long as a controller is connected
      Before=moonlight.service
      Requires=moonlight.service
      StopPropagatedFrom=controller-active.target

      [Install]
      WantedBy=controller-active.target

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      # Save the active (default) tty such that we can restore it
      ExecStart=/usr/local/lib/moonlight-autolauncher/switch-tty.sh
      ExecStop=/usr/local/lib/moonlight-autolauncher/restore-tty.sh
      ExecStopPost=systemctl stop moonlight.service

/etc/systemd/system/moonlight-pulseaudio.service:
  file.managed:
  - mode: 644
  - contents: |
      [Unit]
      Description=Launch pulseaudio for use with Moonlight
      Before=moonlight.service
      PartOf=moonlight.service

      [Install]
      RequiredBy=moonlight.service

      # Service based on Debian's pulseaudio config
      [Service]
      User=moonlight
      ExecStart=/usr/bin/pulseaudio --daemonize=no --log-target=journal
      LockPersonality=yes
      MemoryDenyWriteExecute=yes
      NoNewPrivileges=yes
      Restart=on-failure
      RestrictNamespaces=yes
      SystemCallArchitectures=native
      SystemCallFilter=@system-service
      # Note that notify will only work if --daemonize=no
      Type=notify
      UMask=0077

service_pulseaudio_enable:
    service.enabled:
    - name: moonlight-pulseaudio.service

service_moonlight_autolauncher_enable:
    service.enabled:
    - name: moonlight-autolauncher.service

