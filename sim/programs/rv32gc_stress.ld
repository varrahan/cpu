ENTRY(_start)
SECTIONS
{
    . = 0;
    .text : { KEEP(*(.text.start)) *(.text .text.*) }
}
