import * as RPopover from "@radix-ui/react-popover";
import * as RHoverCard from "@radix-ui/react-hover-card";
import * as RLabel from "@radix-ui/react-label";

export function Popover() {
  return (
    <>
      <RPopover.Root>
        <RPopover.Trigger>Trigger</RPopover.Trigger>
        <RPopover.Portal>
          <RPopover.Content>
            <RLabel.Root>Label</RLabel.Root>
          </RPopover.Content>
        </RPopover.Portal>
      </RPopover.Root>
      <RHoverCard.Root>
        <RHoverCard.Trigger>Hover</RHoverCard.Trigger>
        <RHoverCard.Content>card</RHoverCard.Content>
      </RHoverCard.Root>
    </>
  );
}
