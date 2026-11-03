import "./index.css";
import {TappyImmersiveComposition} from "./ImmersiveComposition";
import {TappyInspirationVariationCompositions} from "./InspirationVariations";
import {TappyComposition} from "./Composition";
import {TappyMoreSoundsInsertComposition} from "./MoreSoundsInsertComposition";
import {TappySoothingComposition} from "./SoothingComposition";
import {TappyViralComposition} from "./ViralComposition";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <TappyComposition />
      <TappyViralComposition />
      <TappySoothingComposition />
      <TappyInspirationVariationCompositions />
      <TappyImmersiveComposition />
      <TappyMoreSoundsInsertComposition />
    </>
  );
};
