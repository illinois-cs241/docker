poll_host_ping () {
    NETID="$1"
    NETID_PASSWORD="$2"
    VM_NAME="$3"
    MAX_POLL_TIME=${4:-300}  # Max polling time in seconds (default: 300 seconds)
    POLL_INTERVAL=${5:-5}    # Polling interval in seconds (default: 5 seconds)

    STATUS=$(sshpass -p "$NETID_PASSWORD" ssh -o StrictHostKeyChecking=no "$NETID@linux.ews.illinois.edu" 2>/dev/null <<EOF
        # Polling logic to check if VM is reachable
        echo "Pinging $VM_NAME for up to $MAX_POLL_TIME seconds every $POLL_INTERVAL seconds..."
        start_time=\$(date +%s)
        while true; do
            current_time=\$(date +%s)
            elapsed_time=\$((current_time - start_time))

            # Check if elapsed time exceeds max poll time
            if [ "\$elapsed_time" -ge "$MAX_POLL_TIME" ]; then
                echo "off"
                exit 1
            fi

            # Ping the VM to check if it's reachable
            if ping -c 1 "$VM_NAME" &>/dev/null; then
                echo "on"
                exit 0
            fi

            # Wait before the next ping
            sleep "$POLL_INTERVAL"
        done
EOF
    )

    STATUS=$(echo "$STATUS" | tr -d '[:space:]')
    case "$STATUS" in
        *on)
            return 0
            ;;
        *off)
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

power_on_vm () {
    NETID="$1"
    NETID_PASSWORD="$2"
    VM_NAME="$3"

    STATUS=$(sshpass -p "$NETID_PASSWORD" ssh -o StrictHostKeyChecking=no "$NETID@linux.ews.illinois.edu" 2>/dev/null <<EOF
        export VSPHERE="vc.cs.illinois.edu"

        # Step 1: Authenticate and get session ID
        SESSION_RESPONSE=\$(curl -s -u "$NETID:$NETID_PASSWORD" -X POST "https://\$VSPHERE/rest/com/vmware/cis/session")
        SESSION_ID=\$(echo "\$SESSION_RESPONSE" | grep -oP '"value":"\K[^"]+')
        if [ -z "\$SESSION_ID" ]; then
            echo "Failed to authenticate. Please check your NETID and password."
            exit 1
        fi
        echo "Authenticated successfully. Session ID: \$SESSION_ID"

        # Step 2: Get VM ID based on VM name
        VM_RESPONSE=\$(curl -s -X GET "https://\$VSPHERE/rest/vcenter/vm?filter.names=$VM_NAME" \
                    -H "vmware-api-session-id: \$SESSION_ID")
        VM_ID=\$(echo "\$VM_RESPONSE" | grep -oP '"vm":"\K[^"]+')
        if [ -z "\$VM_ID" ]; then
            echo "Failed to find VM: $VM_NAME. Please check the VM name or your permissions."
            exit 1
        fi
        echo "VM ID for $VM_NAME: \$VM_ID"

        # Step 3: Power on the VM
        POWER_ON_RESPONSE=\$(curl -s -X POST "https://\$VSPHERE/rest/vcenter/vm/\$VM_ID/power/start" \
                          -H "vmware-api-session-id: \$SESSION_ID")
        if [ -n "\$POWER_ON_RESPONSE" ]; then
            echo "ok"
        else
            echo "fail"
        fi
EOF
    )
    STATUS=$(echo "$STATUS" | tr -d '[:space:]')
    case "$STATUS" in
        *ok)
            return 0;
            ;;
        *fail)
            return 1;
            ;;
        *)
            return 2;
            ;;
    esac
}

connect_via_ews () {
    sshpass -p "$2" ssh -o StrictHostKeyChecking=no -J "$1@linux.ews.illinois.edu" "$1@$3"
}

connect_directly () {
    sshpass -p "$2" ssh -o StrictHostKeyChecking=no "$1@$3"
}

cs341on() {
    if [ -z "$VM_HOSTNAME" ]; then
        echo "Please set the VM_HOSTNAME environment variable (export VM_HOSTNAME=<your vSphere VM>)" >&2
        return 1
    fi

    if ping -c 1 -W 3 "$VM_HOSTNAME"     > /dev/null 2>&1; then
        echo "Done."
    else
        # Check if the VM is reachable from the jump host
        echo -n "dsingh14@illinois.edu's password: " >&2
        read -s NETID_PASSWORD
        echo >&2
        STATUS=$(sshpass -p "$NETID_PASSWORD" ssh -o StrictHostKeyChecking=no "$NETID@linux.ews.illinois.edu" 2>/dev/null <<EOF
        if ping -c 1 -W 3 "$VM_HOSTNAME" > /dev/null 2>&1; then
            echo "on"
        else
            echo "off"
        fi
EOF
        )
        STATUS=$(echo "$STATUS" | tr -d '[:space:]')
        case "$STATUS" in
            *on)
                echo "Done (connect via EWS)."
                ;;
            *off)
                echo "Your VM is not on!" >&2
                power_on_vm "$NETID" "$NETID_PASSWORD" "$VM_HOSTNAME"
                POWER_ON_RESPONSE=$?
                if [ "$POWER_ON_RESPONSE" -eq 0 ]; then 
                    echo "Waiting up to 5 minutes for VM to come online..."
                    poll_host_ping "$NETID" "$NETID_PASSWORD" "$VM_HOSTNAME"
                    PING_RESPONSE=$?
                    if [ "$PING_RESPONSE" -eq 0 ]; then 
                        echo "Done."
                    else
                        echo "VM did not come online, please try again..."  
                        return 1;
                    fi
                else 
                    echo "Could not power on your VM. Try turning it on from the vSphere UI manually."
                fi
                ;;
            *)
                echo "Unexpected status: $STATUS" >&2
                ;;
        esac
    fi
}

cs341ssh() {
    if [ -z "$VM_HOSTNAME" ]; then
        echo "Please set the VM_HOSTNAME environment variable (export VM_HOSTNAME=<your vSphere VM>)" >&2
        return 1
    fi

    if ping -c 1 -W 3 "$VM_HOSTNAME"     > /dev/null 2>&1; then
        connect_directly "$NETID" "$NETID_PASSWORD" "$VM_HOSTNAME"
    else
        # Check if the VM is reachable from the jump host
        echo -n "dsingh14@illinois.edu's password: " >&2
        read -s NETID_PASSWORD
        echo >&2
        STATUS=$(sshpass -p "$NETID_PASSWORD" ssh -o StrictHostKeyChecking=no "$NETID@linux.ews.illinois.edu" 2>/dev/null <<EOF
        if ping -c 1 -W 3 "$VM_HOSTNAME" > /dev/null 2>&1; then
            echo "on"
        else
            echo "off"
        fi
EOF
        )
        STATUS=$(echo "$STATUS" | tr -d '[:space:]')
        case "$STATUS" in
            *on)
                connect_via_ews "$NETID" "$NETID_PASSWORD" "$VM_HOSTNAME"
                ;;
            *off)
                echo "Your VM is not on!" >&2
                power_on_vm "$NETID" "$NETID_PASSWORD" "$VM_HOSTNAME"
                POWER_ON_RESPONSE=$?
                if [ "$POWER_ON_RESPONSE" -eq 0 ]; then 
                    echo "Waiting up to 5 minutes for VM to come online..."
                    poll_host_ping "$NETID" "$NETID_PASSWORD" "$VM_HOSTNAME"
                    PING_RESPONSE=$?
                    if [ "$PING_RESPONSE" -eq 0 ]; then 
                        echo "$NETID_PASSWORD" | cs341ssh
                        return 0;
                    else
                        echo "VM did not come online, please try again..."  
                        return 1;
                    fi
                else 
                    echo "Could not power on your VM. Try turning it on from the vSphere UI manually."
                fi
                ;;
            *)
                echo "Unexpected status: $STATUS" >&2
                ;;
        esac
    fi
}
