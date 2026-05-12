import * as RTabs from "@radix-ui/react-tabs";
import * as RToggle from "@radix-ui/react-toggle";
import * as RToggleGroup from "@radix-ui/react-toggle-group";
import * as RSeparator from "@radix-ui/react-separator";

export function Tabs() {
  return (
    <>
      <RTabs.Root>
        <RTabs.List>
          <RTabs.Trigger value="a">A</RTabs.Trigger>
        </RTabs.List>
        <RTabs.Content value="a">A content</RTabs.Content>
      </RTabs.Root>
      <RToggle.Root />
      <RToggleGroup.Root type="single">
        <RToggleGroup.Item value="a">A</RToggleGroup.Item>
      </RToggleGroup.Root>
      <RSeparator.Root />
    </>
  );
}
