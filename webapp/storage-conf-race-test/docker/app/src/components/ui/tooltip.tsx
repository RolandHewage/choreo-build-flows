import * as RTooltip from "@radix-ui/react-tooltip";
import * as RAvatar from "@radix-ui/react-avatar";
import * as RScrollArea from "@radix-ui/react-scroll-area";

export function Tooltip() {
  return (
    <RTooltip.Provider>
      <RTooltip.Root>
        <RTooltip.Trigger>?</RTooltip.Trigger>
        <RTooltip.Portal>
          <RTooltip.Content>tip</RTooltip.Content>
        </RTooltip.Portal>
      </RTooltip.Root>
      <RAvatar.Root>
        <RAvatar.Image src="" />
        <RAvatar.Fallback>X</RAvatar.Fallback>
      </RAvatar.Root>
      <RScrollArea.Root>
        <RScrollArea.Viewport>scroll</RScrollArea.Viewport>
        <RScrollArea.Scrollbar orientation="vertical">
          <RScrollArea.Thumb />
        </RScrollArea.Scrollbar>
      </RScrollArea.Root>
    </RTooltip.Provider>
  );
}
