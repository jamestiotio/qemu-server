/usr/bin/kvm \
  -id 8006 \
  -name 'simple,debug-threads=on' \
  -no-shutdown \
  -chardev 'socket,id=qmp,path=/var/run/qemu-server/8006.qmp,server=on,wait=off' \
  -mon 'chardev=qmp,mode=control' \
  -chardev 'socket,id=qmp-event,path=/var/run/qmeventd.sock,reconnect=5' \
  -mon 'chardev=qmp-event,mode=control' \
  -pidfile /var/run/qemu-server/8006.pid \
  -daemonize \
  -smbios 'type=1,uuid=7b10d7af-b932-4c66-b2c3-3996152ec465' \
  -smp '4,sockets=2,cores=2,maxcpus=4' \
  -nodefaults \
  -boot 'menu=on,strict=on,reboot-timeout=1000,splash=/usr/share/qemu-server/bootsplash.jpg' \
  -vnc 'unix:/var/run/qemu-server/8006.vnc,password=on' \
  -cpu kvm64,enforce,+kvm_pv_eoi,+kvm_pv_unhalt,+lahf_lm,+sep \
  -m 8192 \
  -object 'memory-backend-file,id=ram-node0,size=4096M,mem-path=/run/hugepages/kvm/1048576kB,share=on,prealloc=yes' \
  -numa 'node,nodeid=0,cpus=0-1,memdev=ram-node0' \
  -object 'memory-backend-file,id=ram-node1,size=4096M,mem-path=/run/hugepages/kvm/1048576kB,share=on,prealloc=yes' \
  -numa 'node,nodeid=1,cpus=2-3,memdev=ram-node1' \
  -device 'pci-bridge,id=pci.1,chassis_nr=1,bus=pci.0,addr=0x1e' \
  -device 'pci-bridge,id=pci.2,chassis_nr=2,bus=pci.0,addr=0x1f' \
  -device 'vmgenid,guid=c773c261-d800-4348-9f5d-167fadd53cf8' \
  -device 'piix3-usb-uhci,id=uhci,bus=pci.0,addr=0x1.0x2' \
  -device 'usb-tablet,id=tablet,bus=uhci.0,port=1' \
  -device 'VGA,id=vga,bus=pci.0,addr=0x2' \
  -device 'virtio-balloon-pci,id=balloon0,bus=pci.0,addr=0x3' \
  -iscsi 'initiator-name=iqn.1993-08.org.debian:01:aabbccddeeff' \
  -machine 'type=pc'
