package com.gogs.bananagame.games

import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.games.colortrap.ColorTrapGame
import com.gogs.bananagame.games.tankmaze.TankMazeGame
import com.gogs.bananagame.games.pegsolitaire.PegSolitaireGame
import com.gogs.bananagame.games.quickmath.QuickMathGame
import com.gogs.bananagame.games.memory.MemoryGame

/** The master list of games shown in the feed, in the iOS `GameRegistry.all` order. */
object GameRegistry {
    val all: List<GameDefinition> by lazy {
        listOf(
            PegSolitaireGame.definition,
            QuickMathGame.definition,
            MemoryGame.definition,
            TankMazeGame.definition,
            ColorTrapGame.definition,
        )
    }
}
