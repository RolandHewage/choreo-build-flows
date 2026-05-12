import * as RAccordion from "@radix-ui/react-accordion";
import * as RCollapsible from "@radix-ui/react-collapsible";
import * as RProgress from "@radix-ui/react-progress";
import * as RSlider from "@radix-ui/react-slider";
import * as RAspect from "@radix-ui/react-aspect-ratio";

export function Accordion() {
  return (
    <>
      <RAccordion.Root type="single">
        <RAccordion.Item value="a">
          <RAccordion.Header>
            <RAccordion.Trigger>Trigger</RAccordion.Trigger>
          </RAccordion.Header>
          <RAccordion.Content>Content</RAccordion.Content>
        </RAccordion.Item>
      </RAccordion.Root>
      <RCollapsible.Root>
        <RCollapsible.Trigger>open</RCollapsible.Trigger>
        <RCollapsible.Content>collapsed</RCollapsible.Content>
      </RCollapsible.Root>
      <RProgress.Root value={50}>
        <RProgress.Indicator />
      </RProgress.Root>
      <RSlider.Root defaultValue={[50]}>
        <RSlider.Track>
          <RSlider.Range />
        </RSlider.Track>
        <RSlider.Thumb />
      </RSlider.Root>
      <RAspect.Root ratio={16 / 9} />
    </>
  );
}
