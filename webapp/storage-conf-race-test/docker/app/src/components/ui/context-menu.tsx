import * as RContextMenu from "@radix-ui/react-context-menu";

export function ContextMenu() {
  return (
    <RContextMenu.Root>
      <RContextMenu.Trigger>right-click</RContextMenu.Trigger>
      <RContextMenu.Portal>
        <RContextMenu.Content>
          <RContextMenu.Item>Item</RContextMenu.Item>
        </RContextMenu.Content>
      </RContextMenu.Portal>
    </RContextMenu.Root>
  );
}
