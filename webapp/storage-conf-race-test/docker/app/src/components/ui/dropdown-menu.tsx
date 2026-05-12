import * as RDropdownMenu from "@radix-ui/react-dropdown-menu";
import * as RSlot from "@radix-ui/react-slot";
import { Check } from "lucide-react";

export function DropdownMenu() {
  return (
    <RDropdownMenu.Root>
      <RDropdownMenu.Trigger asChild>
        <RSlot.Slot>
          <button>Menu</button>
        </RSlot.Slot>
      </RDropdownMenu.Trigger>
      <RDropdownMenu.Content>
        <RDropdownMenu.Item>
          <Check size={12} /> Item
        </RDropdownMenu.Item>
      </RDropdownMenu.Content>
    </RDropdownMenu.Root>
  );
}
