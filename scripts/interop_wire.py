"""Strict independent delta inspection; never applies a patch."""

def inspect_delta(data):
    cursor = 0

    def take(n):
        nonlocal cursor
        if n < 0 or n > len(data) - cursor:
            raise ValueError('TruncatedInput')
        result = data[cursor:cursor+n]
        cursor += n
        return result

    if take(4) != bytes.fromhex('72730236'):
        raise ValueError('InvalidDelta')
    commands = []
    while cursor < len(data):
        opcode = take(1)[0]
        if opcode == 0:
            if cursor != len(data):
                raise ValueError('TrailingData')
            return commands
        if opcode >= 0x55:
            raise ValueError('InvalidOpcode')
        if opcode <= 0x40:
            length = opcode
        elif opcode <= 0x44:
            length = int.from_bytes(take(1 << (opcode - 0x41)), 'big')
        else:
            offset = int.from_bytes(take(1 << ((opcode - 0x45) // 4)), 'big')
            length = int.from_bytes(take(1 << ((opcode - 0x45) % 4)), 'big')
        if length == 0:
            raise ValueError('InvalidDelta')
        commands.append(('literal', take(length)) if opcode <= 0x44 else ('copy', offset, length))
    raise ValueError('TruncatedInput')


def check_contents(commands, old, new):
    position, copied = 0, 0
    for command in commands:
        if command[0] == 'literal':
            actual = command[1]
        else:
            _, offset, length = command
            if offset > len(old) or length > len(old) - offset:
                raise ValueError('CopyOutOfBounds')
            actual = old[offset:offset+length]
            copied += length
        if len(actual) > len(new) - position or actual != new[position:position+len(actual)]:
            raise ValueError('InstructionContentMismatch')
        position += len(actual)
    if position != len(new):
        raise ValueError('OutputLengthMismatch')
    return copied
