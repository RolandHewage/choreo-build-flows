import * as RHoverCard from "@radix-ui/react-hover-card";
import { clsx } from "clsx";
import { cva } from "class-variance-authority";
import { twMerge } from "tailwind-merge";

const cn = (...inputs: Parameters<typeof clsx>) => twMerge(clsx(inputs));
const button = cva("inline-flex");

export function HoverCard() {
  return (
    <RHoverCard.Root>
      <RHoverCard.Trigger className={cn(button())}>hover me</RHoverCard.Trigger>
      <RHoverCard.Portal>
        <RHoverCard.Content>card body</RHoverCard.Content>
      </RHoverCard.Portal>
    </RHoverCard.Root>
  );
}
