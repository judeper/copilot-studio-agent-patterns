import * as React from "react";
import { Text, tokens } from "@fluentui/react-components";
import type { AssistantCard } from "./types";
import { CardItem } from "./CardItem";

interface CardGalleryProps {
    cards: AssistantCard[];
    onSelectCard: (cardId: string) => void;
}

export const CardGallery: React.FC<CardGalleryProps> = ({ cards, onSelectCard }) => {
    if (cards.length === 0) {
        return (
            <div className="card-gallery-empty">
                <Text
                    size={400}
                    style={{ color: tokens.colorNeutralForeground3 }}
                >
                    No cards match the current filters.
                </Text>
            </div>
        );
    }

    return (
        <div className="card-gallery">
            {cards.map((card) => (
                <CardItem
                    key={card.id}
                    card={card}
                    onClick={onSelectCard}
                />
            ))}
        </div>
    );
};
