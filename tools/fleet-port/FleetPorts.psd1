# FleetHacker port blocks: ONE declaration per tool. APPROVED 2026-10-25; see PORTS.md.
# Start = default port. Size = contiguous ports the tool may walk upward through when busy. Blocks never overlap.
# Policy: reuse | restart | multi | exclusive (see CONVENTIONS.md "Port blocks and self-detection").
@{
    'phoenix-lai-api'    = @{ Start = 1234;  Size = 1;  Policy = 'exclusive' }
    'data-noodler'       = @{ Start = 8079;  Size = 3;  Policy = 'reuse' }
    'lasso'              = @{ Start = 8765;  Size = 2;  Policy = 'reuse' }
    'synapse'            = @{ Start = 8767;  Size = 1;  Policy = 'reuse' }
    'lasso-dev'          = @{ Start = 8768;  Size = 1;  Policy = 'restart' }
    'keystone'           = @{ Start = 8769;  Size = 2;  Policy = 'reuse' }
    'mailhawk'           = @{ Start = 8771;  Size = 3;  Policy = 'exclusive' }
    'eight-bells'        = @{ Start = 8774;  Size = 1;  Policy = 'reuse' }
    'scrimshaw'          = @{ Start = 8775;  Size = 1;  Policy = 'reuse' }
    'fairlead'           = @{ Start = 8776;  Size = 1;  Policy = 'reuse' }
    'windlass'           = @{ Start = 8777;  Size = 3;  Policy = 'exclusive' }
    'phoenix-lai-server' = @{ Start = 8780;  Size = 10; Policy = 'exclusive' }
    'phoenix-lai-client' = @{ Start = 8790;  Size = 9;  Policy = 'multi' }
    'phoenix-lai-dev'    = @{ Start = 8799;  Size = 1;  Policy = 'restart' }
    'semaphore'          = @{ Start = 8800;  Size = 3;  Policy = 'reuse' }
    'periscope'          = @{ Start = 8803;  Size = 3;  Policy = 'reuse' }
    'halyard'            = @{ Start = 8806;  Size = 3;  Policy = 'reuse' }
    # PROPOSED (2026-11-08): Lazarette still binds 8765 (inside SnapShackle's block) with an OS-port fallback until its repo moves here.
    'lazarette'          = @{ Start = 8809;  Size = 1;  Policy = 'reuse' }
    'talkforge'          = @{ Start = 25000; Size = 9;  Policy = 'reuse' }
    # TalkForge's speech server (talkforge serve), started on demand by Start-FleetService; fixed so callers can find it.
    'talkforge-speech'   = @{ Start = 25009; Size = 1;  Policy = 'reuse' }
}
