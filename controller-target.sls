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
      #StopPropagatedFrom=dev-input-game-controller.device
      #After=dev-input-game-controller.device
      #Requisite=dev-input-game-controller.device
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
     OnActiveSec=5min
     AccuracySec=20s
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
      ACTION=="add", ATTRS{name}=="8BitDo Ultimate 2 Wireless Controller", KERNEL=="event[0-9]*", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/input/game-controller", ENV{SYSTEMD_WANTS}="controller-connected.service"

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
      Environment=SUNSHINE_IP=192.168.1.27
      Environment="QT_QPA_EGLFS_KMS_CONFIG=/etc/moonlight/eglfs.json"
      # Check the KMS config exists
      ExecStartPre=test -f $QT_QPA_EGLFS_KMS_CONFIG
      ExecStart=moonlight-qt --1440 --fps $STREAM_FPS --performance-overlay stream $SUNSHINE_IP "Desktop"
      Restart=on-failure


/etc/systemd/system/moonlight-autolauncher.service:
  file.managed:
  - mode: 644
  - contents: |
      [Unit]
      Description=Keeps Moonshine launched as long as a controller is connected
      Before=moonlight.service
      Requires=moonlight.service
      # Stop moonlight if the autolauncher shuts down
      PropagatesStopTo=moonlight.service
      BindsTo=controller-active.target

      [Install]
      WantedBy=controller-active.target

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      # Save the active (default) tty such that we can restore it
      ExecStartPre=cp /sys/class/tty/tty0/active /run/moonlight-autolaunch-previous-tty 
      ExecStart=chvt 4
      ExecStop=sh -c 'chvt $(cat /run/moonlight-autolaunch-previous-tty)'

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

# Stop pulseaudio starting
