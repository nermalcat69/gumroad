import * as React from "react";
import { createCast } from "ts-safe-cast";

import { Taxonomy } from "$app/utils/discover";
import { register } from "$app/utils/serverComponentUtil";

import { Layout as DiscoverLayout } from "$app/components/Discover/Layout";
import { Layout, Props } from "$app/components/Product/Layout";

const ProductPage = (props: Props & {
  taxonomy_path: string | null;
  source_taxonomy: string | null;
  taxonomies_for_nav: Taxonomy[]
}) => {

  const useDarkBackground = !props.source_taxonomy;
  const taxonomyToUse = props.source_taxonomy ?? props.taxonomy_path ?? undefined;

  return (
    <DiscoverLayout
      taxonomyPath={useDarkBackground ? undefined : taxonomyToUse}
      taxonomiesForNav={props.taxonomies_for_nav}
      showTaxonomy={true}
      className="custom-sections"
      forceDomain
      darkTheme={useDarkBackground}
    >
      <Layout cart hasHero {...props} />
      {/* render an empty div for the add section button */}
      {"products" in props ? <div /> : null}
    </DiscoverLayout>
  );
};

export default register({ component: ProductPage, propParser: createCast() });
