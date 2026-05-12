import * as RNav from "@radix-ui/react-navigation-menu";

export function NavigationMenu() {
  return (
    <RNav.Root>
      <RNav.List>
        <RNav.Item>
          <RNav.Trigger>Item</RNav.Trigger>
          <RNav.Content>panel</RNav.Content>
        </RNav.Item>
      </RNav.List>
      <RNav.Viewport />
    </RNav.Root>
  );
}
