package com.gogs.bananagame.games

import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.games.spiralgalaxies.SpiralGalaxiesGame
import com.gogs.bananagame.games.compounddash.CompoundDashGame
import com.gogs.bananagame.games.breach.BreachGame
import com.gogs.bananagame.games.nuggethook.NuggetHookGame
import com.gogs.bananagame.games.cupshuffle.CupShuffleGame
import com.gogs.bananagame.games.slide2048.Slide2048Game
import com.gogs.bananagame.games.turboracer.TurboRacerGame
import com.gogs.bananagame.games.statuemaze.StatueMazeGame
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
            StatueMazeGame.definition,
            TurboRacerGame.definition,
            Slide2048Game.definition,
            CupShuffleGame.definition,
            NuggetHookGame.definition,
            BreachGame.definition,
            CompoundDashGame.definition,
            SpiralGalaxiesGame.definition,
        )
    }
}
