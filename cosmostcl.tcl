set telemetry [dict create]
set current_tlm ""

set current_item ""
set current_conv ""

set handling_conv 0


proc decode {required optional line} {
    if {[llength line] < [llength required]} {
        error MISSINGFIELDS "Invalid number of fields in '$line'"
    }

    set fields [concat $required $optional]

    set result [list]

    lmap field $fields item [lrange $line 1 end] {
        if {$field eq "" || $item eq ""} {
            break
        }

        lappend result $field
        lappend result $item
    }

    return $result
}

proc push_tlm {} {
    global telemetry current_tlm
    if {![string equal $current_tlm ""]} {
        set target [dict get $current_tlm target]
        set command [dict get $current_tlm command]
        set name [list $target $command]
        dict set telemetry $name $current_tlm
    }
    set $current_tlm [list]
}

proc push_item {} {
    global current_tlm current_item

    if {![string equal $current_item ""] && ![string equal $current_tlm ""]} {
        set items [dict get $current_tlm items]
        lappend items $current_item
        dict set current_tlm items $items
    }

    set current_item ""
}

proc handle_telemetry {line} {
    global telemetry current_tlm

    set required [list target command endianness]
    set optional [list description]
    set tlm [decode $required $optional $line]

    # add next offset for use with append_* items
    dict set tlm nextoffset 0

    # add list of telemetry items
    dict set tlm items [list]

    push_tlm

    set current_tlm $tlm
}

proc handle_item {line} {
    global current_item current_tlm

    set required [list name bitoffset bitsize datatype]
    set optional [list description endianness]
    set item [decode $required $optional $line]

    push_item

    set current_item $item
}

proc handle_id_item {line} {
    global current_item

    set required [list name bitoffset bitsize datatype idvalue]
    set optional [list description endianness]
    set item [decode $required $optional $line]

    push_item

    set current_item $item
}

proc handle_append_item {line} {
    global current_item current_tlm

    set required [list name bitsize datatype]
    set optional [list description endianness]
    set item [decode $required $optional line]

    set bitoffset [dict get $current_tlm nextoffset]
    dict set fields bitoffset $bitoffset
    dict set current_tlm nextoffset [expr $bitoffset [dict get $fields bitsize]]

    push_item

    set current_item $item
}

proc handle_append_id_item {line} {
    global current_item current_tlm

    set required [list name bitsize datatype idvalue]
    set optional [list description endianness]
    set item [decode $required $optional $line]

    set bitoffset [dict get $current_tlm nextoffset]
    dict set item bitoffset $bitoffset
    dict set current_tlm nextoffset [expr $bitoffset [dict get $item bitsize]]

    push_item

    set current_item $item
}

proc handle_array {line} {
    global current_item

    set required [list name bitoffset bitsize datatype arraybitsize]
    set optional [list description endianness]
    set item [decode $required $optional $line]

    push_item

    set current_item $item
}

proc handle_append_array {line} {
    global current_item current_tlm

    set required [list name bitsize datatype arraybitsize]
    set optional [list description endianness]
    set item [decode $required $optional $line]

    set bitoffset [dict get $current_tlm nextoffset]
    dict set item bitoffset $bitoffset
    dict set current_tlm nextoffset [expr $bitoffset [dict get $item bitsize]]

    push_item

    set current_item $item
}

proc handle_state {line} {
    global current_item

    set required [list key value color]
    set state [decode $required "" $line]

    dict update current_item states statesvar {
        if {![info exists statesvar]} {
            set statesvar ""
        }
        lappend statesvar $state
    }
}

proc handle_conv_start {line} {
    global current_conv handling_conv

    set required [list datatype bitsize]
    set conv [decode $required "" $line]

    set current_conv $conv
    set handling_conv 1
}

proc handle_conv_end {line} {
    global current_conv current_item handling_conv

    if {[string equal current_conv ""]} {
        error UNEXPECTEDCONVEND "Expected conversion end"
    }

    dict set current_item conv $current_conv
    set current_conv ""
    set handling_conv 0
}

proc handle_poly_conv {line} {
    global current_item

    if {[llength $line] < 2} {
        error MISSINGPOLY "Poly conversion requires at least 1 coefficent"
    }

    set conv [lrange $line 1 end]

    dict set current_item polyconv $conv
}

proc handle_seg_poly_conv {line} {
    global current_item

    if {[llength $line] < 3} {
        error MISSINGPOLY "Segment Poly conversion requires at least 1 coefficent"
    }

    set conv [lrange $line 1 end]

    dict set current_item segpolyconv $conv
}

proc handle_select_tlm {line} {
    global current_tlm telemetry

    push_item
    push_tlm

    set tlm_name [lrange $line 1 end]
    if {![dict exists $telemetry $tlm_name]} {
        error SELECTERROR "Tried to select an unknown telemetry target in '$line'"
    }
    set current_tlm [dict get $telemetry $tlm_name]
}

proc handle_select_item {line} {
    global current_item current_tlm

    set item_name [lrange $line 1 end]
    set items [dict get $current_tlm items]
    set index 0
    foreach item $items {
        if {[string equal $item_name [dict get $item name]]} {
            set current_item $item
            break
        }
        incr index
    }

    if {$index >= [llength $items]} {
        error SELECTITEMNOTFOUND "Tried to select an unknown item in '$line'"
    }

    set items [lreplace $items $index $index]
    dict set current_tlm items $items
}

proc handle_modifier {line} {
    global current_item
    lappend current_item $line
}

proc handle_description {line} {
    global current_item

    if {[llength $line]} {
        error INVALIDDESCRIPTION "Description modifier requires a description in line '$line'"
    }

    dict set current_item description [lrange $line 1 1]
}

proc handle_line {line} {
    global current_conv handling_conv

    set line [string trim $line]

    if {[llength $line] != 0} {
        if {$handling_conv && ![string equal [lindex $line 0] GENERIC_READ_CONVERSION_END]} {
            lappend current_conv $line
        } else {
            # TODO missing limit group
            #      limit group item
            #      delete item
            #      allow_short
            #      hidden packet
            #      overlap items
            #      limits, limit_response
            #      meta data at packet levels
            #      processor is not defined- would have to call out to ruby with COSMOS dependency
            # TODO consider using a dictionary to compact this switch
            switch -nocase [lindex $line 0] {
                TELEMETRY { handle_telemetry $line }
                ITEM { handle_item $line }
                ID_ITEM { handle_id_item $line }
                APPEND_ITEM { handle_append_item $line }
                APPEND_ID_ITEM { handle_append_id_item $line }
                APPEND_ARRAY_ITEM { handle_append_array $line }
                ARRAY_ITEM { handle_array $line }
                STATE { handle_state $line }
                ITEM { handle_state $line }
                GENERIC_READ_CONVERSION_START { handle_conv_start $line }
                GENERIC_READ_CONVERSION_END { handle_conv_end $line }
                POLY_READ_CONVERSION { handle_poly_conv $line }
                SEG_POLY_READ_CONVERSION { handle_seg_poly_conv $line }
                SELECT_TELEMETRY { handle_select_tlm $line }
                SELECT_ITEM { handle_select_item $line }
                FORMAT_STRING { handle_modifier $line }
                UNITS { handle_modifier $line }
                META { handle_modifier $line }
                READ_CONVERSION { handle_modifier $line }
                DESCRIPTION { handle_description $line }
                default { error UNEXPECTEDLINE "Unexpected line '$line'" }
            }
        }
    }
}

proc pptelemetry {tlm} {
    dict for {key value} $tlm {
        if {[string equal -nocase $key ITEMS]} {
            puts "ITEMS"
            foreach item $value {
                puts "\t$item"
            }
        } else {
            puts "$key $value"
        }
    }
}

proc parse_cosmos {filename} {
    set fp [open $filename r]
    set data [read $fp]
    close $fp

    set lines [split $data "\n"]

    foreach line $lines {
        handle_line $line
    }

    push_item
    push_tlm
}

parse_cosmos "example.txt"
pptelemetry [dict get $telemetry {TARGET HS}]

